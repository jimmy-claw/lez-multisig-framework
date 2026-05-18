#include "LezMultisigBackend.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtConcurrent/QtConcurrent>

// C FFI — resolved at runtime via dlopen (the .so is co-located with the plugin).
extern "C" {
    char* lez_multisig_create(const char* args_json);
    char* lez_multisig_propose(const char* args_json);
    char* lez_multisig_approve(const char* args_json);
    char* lez_multisig_reject(const char* args_json);
    char* lez_multisig_execute(const char* args_json);
    char* lez_multisig_list_proposals(const char* args_json);
    char* lez_multisig_get_state(const char* args_json);
    void  lez_multisig_free_string(char* s);
}

// ── Construction ──────────────────────────────────────────────────────────────

LezMultisigBackend::LezMultisigBackend(LogosAPI* /*api*/, QObject* parent)
    : QObject(parent)
    , m_walletPath(qEnvironmentVariable("NSSA_WALLET_HOME_DIR", ".scaffold/wallet"))
    , m_programIdHex(qEnvironmentVariable("LEZ_MULTISIG_PROGRAM_ID_HEX"))
    , m_settings("logos-co", "lez-multisig")
{
    loadPersistedMultisigs();
}

LezMultisigBackend::~LezMultisigBackend() = default;

// ── Config setters ────────────────────────────────────────────────────────────

void LezMultisigBackend::setWalletPath(const QString& v) {
    if (m_walletPath == v) return;
    m_walletPath = v;
    m_settings.setValue("walletPath", v);
    emit walletPathChanged();
}

void LezMultisigBackend::setProgramIdHex(const QString& v) {
    if (m_programIdHex == v) return;
    m_programIdHex = v;
    m_settings.setValue("programIdHex", v);
    emit programIdHexChanged();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

QJsonObject LezMultisigBackend::baseArgs() const {
    return QJsonObject{
        {"wallet_path",    m_walletPath},
        {"program_id_hex", m_programIdHex},
    };
}

QJsonObject LezMultisigBackend::baseArgsWithKey() const {
    QJsonObject a = baseArgs();
    a["create_key"] = m_currentCreateKey;
    return a;
}

QString LezMultisigBackend::callFfi(FfiFn fn, const QJsonObject& args) {
    QByteArray json = QJsonDocument(args).toJson(QJsonDocument::Compact);
    char* raw = fn(json.constData());
    if (!raw) return R"({"success":false,"error":"null return from FFI"})";
    QString result = QString::fromUtf8(raw);
    lez_multisig_free_string(raw);
    return result;
}

void LezMultisigBackend::dispatchFfi(const QString& operation, std::function<QString()> fn) {
    if (m_busy) return;
    m_busy = true;
    emit busyChanged();

    auto* watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcher<QString>::finished, this, [this, watcher, operation]() {
        handleFfiResult(operation, watcher->result());
        watcher->deleteLater();
        m_busy = false;
        emit busyChanged();
    });
    watcher->setFuture(QtConcurrent::run(fn));
}

void LezMultisigBackend::handleFfiResult(const QString& operation, const QString& result) {
    QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();

    if (!obj.value("success").toBool()) {
        m_lastError = obj.value("error").toString(result);
        emit lastErrorChanged();
        emit operationError(operation, m_lastError);
        return;
    }

    m_lastError.clear();
    emit lastErrorChanged();

    if (obj.contains("tx_hash")) {
        m_lastTxHash = obj.value("tx_hash").toString();
        emit lastTxHashChanged();
        emit operationSuccess(operation, m_lastTxHash);
        QTimer::singleShot(1200, this, &LezMultisigBackend::refreshCurrentMultisig);
        QTimer::singleShot(1200, this, &LezMultisigBackend::refreshProposals);
    }

    // get_state response
    if (obj.contains("multisig_state_id")) {
        updateMultisigInList(obj);
        m_currentMultisig = obj.toVariantMap();
        emit currentMultisigChanged();
    }

    // list_proposals response
    if (obj.contains("proposals")) {
        m_proposals.clear();
        for (const QJsonValue& v : obj.value("proposals").toArray())
            m_proposals.append(v.toObject().toVariantMap());
        emit proposalsChanged();
    }
}

// ── Local persistence ─────────────────────────────────────────────────────────

void LezMultisigBackend::persistMultisigs() {
    QJsonArray arr;
    for (const QVariant& v : m_multisigs)
        arr.append(QJsonObject::fromVariantMap(v.toMap()));
    m_settings.setValue("multisigs", QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact)));
}

void LezMultisigBackend::loadPersistedMultisigs() {
    QString raw = m_settings.value("multisigs", "[]").toString();
    QJsonArray arr = QJsonDocument::fromJson(raw.toUtf8()).array();
    m_multisigs.clear();
    for (const QJsonValue& v : arr)
        m_multisigs.append(v.toObject().toVariantMap());

    // Restore config if not set via env
    if (m_walletPath.isEmpty() || m_walletPath == ".scaffold/wallet")
        m_walletPath = m_settings.value("walletPath", m_walletPath).toString();
    if (m_programIdHex.isEmpty())
        m_programIdHex = m_settings.value("programIdHex").toString();
}

void LezMultisigBackend::updateMultisigInList(const QJsonObject& state) {
    QString createKey = state.value("create_key").toString(m_currentCreateKey);
    QVariantMap entry{
        {"create_key",       createKey},
        {"multisig_state_id", state.value("multisig_state_id").toString()},
        {"threshold",        state.value("threshold").toInt()},
        {"member_count",     state.value("member_count").toInt()},
        {"transaction_index", static_cast<qint64>(state.value("transaction_index").toDouble())},
    };

    for (int i = 0; i < m_multisigs.size(); ++i) {
        if (m_multisigs[i].toMap().value("create_key").toString() == createKey) {
            m_multisigs[i] = entry;
            emit multisigsChanged();
            persistMultisigs();
            return;
        }
    }
    // Not in list — add it
    m_multisigs.append(entry);
    emit multisigsChanged();
    persistMultisigs();
}

// ── Multisig list management ──────────────────────────────────────────────────

void LezMultisigBackend::loadMultisig(const QString& createKey) {
    if (createKey.isEmpty() || m_programIdHex.isEmpty()) return;
    QJsonObject args = baseArgs();
    args["create_key"] = createKey;
    dispatchFfi("get_state", [this, args]() {
        return callFfi(lez_multisig_get_state, args);
    });
}

void LezMultisigBackend::selectMultisig(const QString& createKey) {
    if (m_currentCreateKey == createKey) return;
    m_currentCreateKey = createKey;
    emit currentCreateKeyChanged();
    m_currentMultisig = {};
    emit currentMultisigChanged();
    m_proposals.clear();
    emit proposalsChanged();

    if (!createKey.isEmpty()) {
        loadMultisig(createKey);
    }
}

void LezMultisigBackend::removeLocalMultisig(const QString& createKey) {
    for (int i = 0; i < m_multisigs.size(); ++i) {
        if (m_multisigs[i].toMap().value("create_key").toString() == createKey) {
            m_multisigs.removeAt(i);
            emit multisigsChanged();
            persistMultisigs();
            if (m_currentCreateKey == createKey)
                selectMultisig({});
            return;
        }
    }
}

// ── Write instructions ────────────────────────────────────────────────────────

void LezMultisigBackend::createMultisig(quint32 threshold, const QStringList& members, const QString& createKey) {
    QJsonArray memberArr;
    for (const QString& m : members) memberArr.append(m);
    QJsonObject args = baseArgs();
    args["threshold"]  = static_cast<int>(threshold);
    args["members"]    = memberArr;
    args["create_key"] = createKey;
    dispatchFfi("create_multisig", [this, args]() {
        return callFfi(lez_multisig_create, args);
    });
}

void LezMultisigBackend::approve(quint64 proposalIndex) {
    QJsonObject args = baseArgsWithKey();
    args["proposal_index"] = static_cast<qint64>(proposalIndex);
    dispatchFfi("approve", [this, args]() {
        return callFfi(lez_multisig_approve, args);
    });
}

void LezMultisigBackend::reject(quint64 proposalIndex) {
    QJsonObject args = baseArgsWithKey();
    args["proposal_index"] = static_cast<qint64>(proposalIndex);
    dispatchFfi("reject", [this, args]() {
        return callFfi(lez_multisig_reject, args);
    });
}

void LezMultisigBackend::execute(quint64 proposalIndex) {
    QJsonObject args = baseArgsWithKey();
    args["proposal_index"] = static_cast<qint64>(proposalIndex);
    dispatchFfi("execute", [this, args]() {
        return callFfi(lez_multisig_execute, args);
    });
}

void LezMultisigBackend::proposeAddMember(const QString& newMember) {
    QJsonObject payload{{"config_action", QJsonObject{{"AddMember", QJsonObject{{"new_member", newMember}}}}}};
    QJsonObject args = baseArgsWithKey();
    args["pda_seeds"] = QJsonArray{};
    args["payload"]   = payload;
    dispatchFfi("propose_add_member", [this, args]() {
        return callFfi(lez_multisig_propose, args);
    });
}

void LezMultisigBackend::proposeRemoveMember(const QString& member) {
    QJsonObject payload{{"config_action", QJsonObject{{"RemoveMember", QJsonObject{{"member", member}}}}}};
    QJsonObject args = baseArgsWithKey();
    args["pda_seeds"] = QJsonArray{};
    args["payload"]   = payload;
    dispatchFfi("propose_remove_member", [this, args]() {
        return callFfi(lez_multisig_propose, args);
    });
}

void LezMultisigBackend::proposeChangeThreshold(quint32 newThreshold) {
    QJsonObject payload{{"config_action", QJsonObject{{"ChangeThreshold", QJsonObject{{"new_threshold", static_cast<int>(newThreshold)}}}}}};
    QJsonObject args = baseArgsWithKey();
    args["pda_seeds"] = QJsonArray{};
    args["payload"]   = payload;
    dispatchFfi("propose_change_threshold", [this, args]() {
        return callFfi(lez_multisig_propose, args);
    });
}

void LezMultisigBackend::proposeTransaction(const QString& payloadJson, const QStringList& pdaSeeds) {
    QJsonObject payload = QJsonDocument::fromJson(payloadJson.toUtf8()).object();
    QJsonArray seeds;
    for (const QString& s : pdaSeeds) seeds.append(s);
    QJsonObject args = baseArgsWithKey();
    args["pda_seeds"] = seeds;
    args["payload"]   = payload;
    dispatchFfi("propose_transaction", [this, args]() {
        return callFfi(lez_multisig_propose, args);
    });
}

// ── Refresh ───────────────────────────────────────────────────────────────────

void LezMultisigBackend::refreshCurrentMultisig() {
    if (m_currentCreateKey.isEmpty() || m_busy) return;
    QJsonObject args = baseArgsWithKey();
    QThreadPool::globalInstance()->start([this, args]() {
        QString result = callFfi(lez_multisig_get_state, args);
        QMetaObject::invokeMethod(this, [this, result]() {
            QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();
            if (obj.value("success").toBool()) {
                updateMultisigInList(obj);
                m_currentMultisig = obj.toVariantMap();
                emit currentMultisigChanged();
            }
        }, Qt::QueuedConnection);
    });
}

void LezMultisigBackend::refreshProposals() {
    if (m_currentCreateKey.isEmpty() || m_busy) return;
    QString stateId = m_currentMultisig.value("multisig_state_id").toString();
    if (stateId.isEmpty()) return;
    QJsonObject args = baseArgs();
    args["multisig_state"] = stateId;
    QThreadPool::globalInstance()->start([this, args]() {
        QString result = callFfi(lez_multisig_list_proposals, args);
        QMetaObject::invokeMethod(this, [this, result]() {
            QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();
            if (obj.value("success").toBool() && obj.contains("proposals")) {
                m_proposals.clear();
                for (const QJsonValue& v : obj.value("proposals").toArray())
                    m_proposals.append(v.toObject().toVariantMap());
                emit proposalsChanged();
            }
        }, Qt::QueuedConnection);
    });
}
