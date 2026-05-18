#pragma once

#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QSettings>
#include <QString>
#include <QTimer>
#include <QVariantList>

class LogosAPI;

class LezMultisigBackend : public QObject {
    Q_OBJECT

    // ── Config ────────────────────────────────────────────────────────────────
    Q_PROPERTY(QString walletPath    READ walletPath    WRITE setWalletPath    NOTIFY walletPathChanged)
    Q_PROPERTY(QString programIdHex  READ programIdHex  WRITE setProgramIdHex  NOTIFY programIdHexChanged)

    // ── Known multisig list (locally persisted) ───────────────────────────────
    Q_PROPERTY(QVariantList multisigs       READ multisigs       NOTIFY multisigsChanged)
    Q_PROPERTY(QString      currentCreateKey READ currentCreateKey NOTIFY currentCreateKeyChanged)

    // ── Selected multisig state ───────────────────────────────────────────────
    Q_PROPERTY(QVariantMap  currentMultisig  READ currentMultisig  NOTIFY currentMultisigChanged)
    Q_PROPERTY(QVariantList proposals        READ proposals        NOTIFY proposalsChanged)

    // ── Async status ──────────────────────────────────────────────────────────
    Q_PROPERTY(bool    busy        READ busy        NOTIFY busyChanged)
    Q_PROPERTY(QString lastError   READ lastError   NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastTxHash  READ lastTxHash  NOTIFY lastTxHashChanged)

public:
    explicit LezMultisigBackend(LogosAPI* api, QObject* parent = nullptr);
    ~LezMultisigBackend() override;

    QString      walletPath()      const { return m_walletPath; }
    QString      programIdHex()    const { return m_programIdHex; }
    QVariantList multisigs()       const { return m_multisigs; }
    QString      currentCreateKey() const { return m_currentCreateKey; }
    QVariantMap  currentMultisig() const { return m_currentMultisig; }
    QVariantList proposals()       const { return m_proposals; }
    bool         busy()            const { return m_busy; }
    QString      lastError()       const { return m_lastError; }
    QString      lastTxHash()      const { return m_lastTxHash; }

    void setWalletPath(const QString& v);
    void setProgramIdHex(const QString& v);

    // ── Multisig list management ──────────────────────────────────────────────
    Q_INVOKABLE void loadMultisig(const QString& createKey);
    Q_INVOKABLE void selectMultisig(const QString& createKey);
    Q_INVOKABLE void removeLocalMultisig(const QString& createKey);

    // ── Write instructions ────────────────────────────────────────────────────
    Q_INVOKABLE void createMultisig(quint32 threshold, const QStringList& members, const QString& createKey);
    Q_INVOKABLE void approve(quint64 proposalIndex);
    Q_INVOKABLE void reject(quint64 proposalIndex);
    Q_INVOKABLE void execute(quint64 proposalIndex);

    // Config-change proposals (construct payload internally)
    Q_INVOKABLE void proposeAddMember(const QString& newMember);
    Q_INVOKABLE void proposeRemoveMember(const QString& member);
    Q_INVOKABLE void proposeChangeThreshold(quint32 newThreshold);

    // Raw transaction proposal (advanced — caller supplies full payload JSON)
    Q_INVOKABLE void proposeTransaction(const QString& payloadJson, const QStringList& pdaSeeds);

    // ── Refresh ───────────────────────────────────────────────────────────────
    Q_INVOKABLE void refreshProposals();
    Q_INVOKABLE void refreshCurrentMultisig();

signals:
    void walletPathChanged();
    void programIdHexChanged();
    void multisigsChanged();
    void currentCreateKeyChanged();
    void currentMultisigChanged();
    void proposalsChanged();
    void busyChanged();
    void lastErrorChanged();
    void lastTxHashChanged();

    void operationSuccess(const QString& operation, const QString& txHash);
    void operationError(const QString& operation, const QString& error);

private:
    using FfiFn = char* (*)(const char*);

    void        dispatchFfi(const QString& operation, std::function<QString()> fn);
    void        dispatchFfiRefresh(std::function<QString()> fn,
                                   std::function<void(const QJsonObject&)> apply);
    void        handleFfiResult(const QString& operation, const QString& result);
    QString     callFfi(FfiFn fn, const QJsonObject& args);
    QJsonObject baseArgs() const;
    QJsonObject baseArgsWithKey() const;

    void persistMultisigs();
    void loadPersistedMultisigs();
    void updateMultisigInList(const QJsonObject& state);

    QString      m_walletPath;
    QString      m_programIdHex;
    QString      m_currentCreateKey;

    QVariantList m_multisigs;
    QVariantMap  m_currentMultisig;
    QVariantList m_proposals;

    bool    m_busy       = false;
    QString m_lastError;
    QString m_lastTxHash;

    QSettings m_settings;
};
