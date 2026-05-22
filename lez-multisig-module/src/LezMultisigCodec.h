// Hand-written — NOT generated. Provides QML-callable encode/decode wrappers
// for the Phase 1 IDL codec FFI (lez_multisig_encode/decode_instruction).
#pragma once

#include <QObject>
#include <QString>

extern "C" {
    char* lez_multisig_encode_instruction(const char* idl_json, const char* ix_name, const char* args_json);
    char* lez_multisig_decode_instruction(const char* idl_json, const char* words_json);
    char* lez_multisig_get_idl();
    void  lez_multisig_free_string(char* s);
}

class LezMultisigCodec : public QObject {
    Q_OBJECT
public:
    explicit LezMultisigCodec(QObject* parent = nullptr) : QObject(parent) {}

    // Encode named instruction args to risc0 u32 words.
    // idlJson:  SpelIdl JSON string
    // ixName:   instruction name (e.g. "transfer_tokens")
    // argsJson: JSON object {"arg_name": value, ...}
    // Returns: {"success": true, "result": {"words": [...], "hex": "0x..."}}
    //       or {"success": false, "error": "..."}
    Q_INVOKABLE QString encodeInstruction(const QString& idlJson,
                                          const QString& ixName,
                                          const QString& argsJson) const
    {
        char* raw = lez_multisig_encode_instruction(
            idlJson.toUtf8().constData(),
            ixName.toUtf8().constData(),
            argsJson.toUtf8().constData());
        if (!raw) return QStringLiteral(R"({"success":false,"error":"null response from FFI"})");
        QString result = QString::fromUtf8(raw);
        lez_multisig_free_string(raw);
        return result;
    }

    // Decode instruction data (JSON array of u32 words) to human-readable args.
    // idlJson:   SpelIdl JSON string
    // wordsJson: JSON array of u32 values  (e.g. "[0,1000,0,1,2,...]")
    // Returns: {"success": true, "result": {"instruction": "name", "args": {...}}}
    //       or {"success": false, "error": "..."}
    Q_INVOKABLE QString decodeInstruction(const QString& idlJson,
                                           const QString& wordsJson) const
    {
        char* raw = lez_multisig_decode_instruction(
            idlJson.toUtf8().constData(),
            wordsJson.toUtf8().constData());
        if (!raw) return QStringLiteral(R"({"success":false,"error":"null response from FFI"})");
        QString result = QString::fromUtf8(raw);
        lez_multisig_free_string(raw);
        return result;
    }

    // Return the multisig program's own IDL JSON (for decoding multisig instructions).
    Q_INVOKABLE QString getMultisigIdl() const
    {
        char* raw = lez_multisig_get_idl();
        if (!raw) return {};
        QString result = QString::fromUtf8(raw);
        lez_multisig_free_string(raw);
        return result;
    }
};
