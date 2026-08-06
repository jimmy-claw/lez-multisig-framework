#pragma once
#include <QObject>

#ifdef LOGOS_STORAGE_AVAILABLE
#include "storage_module_api.h"
#include <memory>
#else
class LogosAPI;
#endif

// Wraps the Logos Storage module for IDL fetching via native IPC.
// Exposed to QML as "storage" context property.
class LezStorageBridge : public QObject {
    Q_OBJECT
public:
    explicit LezStorageBridge(LogosAPI* api, QObject* parent = nullptr)
        : QObject(parent)
    {
#ifdef LOGOS_STORAGE_AVAILABLE
        if (api) m_storage = std::make_unique<StorageModule>(api);
#else
        Q_UNUSED(api)
#endif
    }

    // Returns the raw IDL JSON content for cid, or "" on failure.
    Q_INVOKABLE QString fetchIdl(const QString& cid) {
#ifdef LOGOS_STORAGE_AVAILABLE
        if (m_storage) {
            auto r = m_storage->fetch(cid);
            if (r.success) return r.getString();
        }
#else
        Q_UNUSED(cid)
#endif
        return {};
    }

private:
#ifdef LOGOS_STORAGE_AVAILABLE
    std::unique_ptr<StorageModule> m_storage;
#endif
};
