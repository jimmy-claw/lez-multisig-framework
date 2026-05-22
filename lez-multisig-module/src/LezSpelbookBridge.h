// Hand-written — NOT generated. QML-accessible spelbook bridge: wraps
// lez-registry-ffi (liblez_registry_ffi.so) for program search and IDL fetch.
// Registered as 'spelbook' context property by patch-generated.
// When SPELBOOK_AVAILABLE is not defined (no -DSPELBOOK_FFI_DIR in cmake),
// all methods return {"success":false,"error":"spelbook not linked"}.
#pragma once

#include <QObject>
#include <QString>
#include <QJsonDocument>
#include <QJsonObject>

#ifdef SPELBOOK_AVAILABLE
extern "C" {
    char* lez_storage_fetch_idl(const char* args_json);
    char* lez_registry_search(const char* args_json);
    char* lez_registry_get_by_id(const char* args_json);
    char* lez_registry_register(const char* args_json);
    void  lez_registry_free_string(char* s);
}
#endif

class LezSpelbookBridge : public QObject {
    Q_OBJECT
public:
    explicit LezSpelbookBridge(QObject* parent = nullptr) : QObject(parent) {}

    // Returns true when liblez_registry_ffi.so is linked.
    Q_INVOKABLE bool isAvailable() const {
#ifdef SPELBOOK_AVAILABLE
        return true;
#else
        return false;
#endif
    }

    // Fetch an IDL JSON from Logos Storage (Codex) by CID.
    // Returns: {"success":true,"idl":{...}} or {"success":false,"error":"..."}
    Q_INVOKABLE QString fetchIdl(const QString& storageUrl, const QString& cid) const
    {
#ifdef SPELBOOK_AVAILABLE
        QJsonObject args;
        args["logos_storage_url"] = storageUrl;
        args["cid"]               = cid;
        return callFfi(args, lez_storage_fetch_idl);
#else
        Q_UNUSED(storageUrl); Q_UNUSED(cid);
        return notLinked();
#endif
    }

    // Search cached program entries by name/description/tags.
    // query: substring filter; "" returns all cached entries.
    // Returns: {"success":true,"programs":[...],"count":N}
    Q_INVOKABLE QString searchPrograms(const QString& query) const
    {
#ifdef SPELBOOK_AVAILABLE
        QJsonObject args;
        args["query"] = query;
        return callFfi(args, lez_registry_search);
#else
        Q_UNUSED(query);
        return notLinked();
#endif
    }

    // Fetch a program entry from the on-chain registry by program_id (64 hex chars).
    // Also populates the local spelbook cache for future searchPrograms() calls.
    // Returns: {"success":true,"entry":{...}} or {"success":false,"error":"..."}
    Q_INVOKABLE QString getProgram(const QString& programIdHex,
                                   const QString& sequencerUrl,
                                   const QString& registryProgramIdHex,
                                   const QString& walletPath) const
    {
#ifdef SPELBOOK_AVAILABLE
        QJsonObject args;
        args["program_id"]          = programIdHex;
        args["sequencer_url"]       = sequencerUrl;
        args["registry_program_id"] = registryProgramIdHex;
        args["wallet_path"]         = walletPath;
        return callFfi(args, lez_registry_get_by_id);
#else
        Q_UNUSED(programIdHex); Q_UNUSED(sequencerUrl);
        Q_UNUSED(registryProgramIdHex); Q_UNUSED(walletPath);
        return notLinked();
#endif
    }

    // Register a program in the on-chain registry (full args JSON).
    // Returns: {"success":true,"tx_hash":"..."} or {"success":false,"error":"..."}
    Q_INVOKABLE QString registerProgram(const QString& argsJson) const
    {
#ifdef SPELBOOK_AVAILABLE
        return callFfiRaw(argsJson, lez_registry_register);
#else
        Q_UNUSED(argsJson);
        return notLinked();
#endif
    }

private:
    static QString notLinked() {
        return QStringLiteral(R"({"success":false,"error":"spelbook not linked — rebuild with -DSPELBOOK_FFI_DIR=..."})");
    }

#ifdef SPELBOOK_AVAILABLE
    static QString callFfi(const QJsonObject& args, char* (*fn)(const char*))
    {
        return callFfiRaw(
            QString::fromUtf8(QJsonDocument(args).toJson(QJsonDocument::Compact)),
            fn);
    }

    static QString callFfiRaw(const QString& argsJson, char* (*fn)(const char*))
    {
        char* raw = fn(argsJson.toUtf8().constData());
        if (!raw) return QStringLiteral(R"({"success":false,"error":"FFI returned null"})");
        QString result = QString::fromUtf8(raw);
        lez_registry_free_string(raw);
        return result;
    }
#endif
};
