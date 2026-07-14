#include "storage_module_api.h"

#include <QDebug>

StorageModule::StorageModule(LogosAPI* api) : m_api(api), m_client(api->getClient("storage_module")), m_moduleName(QStringLiteral("storage_module")) {}

LogosObject* StorageModule::ensureReplica() {
    if (!m_eventReplica) {
        LogosObject* replica = m_client->requestObject(m_moduleName);
        if (!replica) {
            qWarning() << "StorageModule: failed to acquire remote object for events on" << m_moduleName;
            return nullptr;
        }
        m_eventReplica = replica;
    }
    return m_eventReplica;
}

bool StorageModule::on(const QString& eventName, RawEventCallback callback) {
    if (!callback) {
        qWarning() << "StorageModule: ignoring empty event callback for" << eventName;
        return false;
    }
    LogosObject* origin = ensureReplica();
    if (!origin) {
        return false;
    }
    m_client->onEvent(origin, eventName, callback);
    return true;
}

bool StorageModule::on(const QString& eventName, EventCallback callback) {
    if (!callback) {
        qWarning() << "StorageModule: ignoring empty event callback for" << eventName;
        return false;
    }
    return on(eventName, [callback](const QString&, const QVariantList& data) {
        callback(data);
    });
}

void StorageModule::setEventSource(LogosObject* source) {
    m_eventSource = source;
}

LogosObject* StorageModule::eventSource() const {
    return m_eventSource;
}

void StorageModule::trigger(const QString& eventName) {
    trigger(eventName, QVariantList{});
}

void StorageModule::trigger(const QString& eventName, const QVariantList& data) {
    if (!m_eventSource) {
        qWarning() << "StorageModule: no event source set for trigger" << eventName;
        return;
    }
    m_client->onEventResponse(m_eventSource, eventName, data);
}

void StorageModule::trigger(const QString& eventName, LogosObject* source, const QVariantList& data) {
    if (!source) {
        qWarning() << "StorageModule: cannot trigger" << eventName << "with null source";
        return;
    }
    m_client->onEventResponse(source, eventName, data);
}

bool StorageModule::init(const QString& cfg) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "init", cfg);
    return _result.toBool();
}

void StorageModule::initAsync(const QString& cfg, std::function<void(bool)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "init", QVariantList() << cfg, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<bool>(v) : false);
    }, timeout);
}

bool StorageModule::start() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "start");
    return _result.toBool();
}

void StorageModule::startAsync(std::function<void(bool)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "start", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<bool>(v) : false);
    }, timeout);
}

LogosResult StorageModule::version() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "version");
    return _result.value<LogosResult>();
}

void StorageModule::versionAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "version", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::dataDir() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "dataDir");
    return _result.value<LogosResult>();
}

void StorageModule::dataDirAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "dataDir", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::peerId() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "peerId");
    return _result.value<LogosResult>();
}

void StorageModule::peerIdAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "peerId", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::debug() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "debug");
    return _result.value<LogosResult>();
}

void StorageModule::debugAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "debug", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::spr() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "spr");
    return _result.value<LogosResult>();
}

void StorageModule::sprAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "spr", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::updateLogLevel(const QString& logLevel) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "updateLogLevel", logLevel);
    return _result.value<LogosResult>();
}

void StorageModule::updateLogLevelAsync(const QString& logLevel, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "updateLogLevel", QVariantList() << logLevel, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::connect(const QString& peerId, const QStringList& peerAddresses) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "connect", peerId, peerAddresses);
    return _result.value<LogosResult>();
}

void StorageModule::connectAsync(const QString& peerId, const QStringList& peerAddresses, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "connect", QVariantList{peerId, peerAddresses}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadUrl(QVariant url, int chunkSize) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadUrl", url, chunkSize);
    return _result.value<LogosResult>();
}

void StorageModule::uploadUrlAsync(QVariant url, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadUrl", QVariantList{url, chunkSize}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadUrl(QVariant url) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadUrl", url);
    return _result.value<LogosResult>();
}

void StorageModule::uploadUrlAsync(QVariant url, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadUrl", QVariantList() << url, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadInit(const QString& filename, int chunkSize) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadInit", filename, chunkSize);
    return _result.value<LogosResult>();
}

void StorageModule::uploadInitAsync(const QString& filename, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadInit", QVariantList{filename, chunkSize}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadInit(const QString& filename) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadInit", filename);
    return _result.value<LogosResult>();
}

void StorageModule::uploadInitAsync(const QString& filename, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadInit", QVariantList() << filename, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadChunk(const QString& sessionId, QVariant chunk) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadChunk", sessionId, chunk);
    return _result.value<LogosResult>();
}

void StorageModule::uploadChunkAsync(const QString& sessionId, QVariant chunk, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadChunk", QVariantList{sessionId, chunk}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadFinalize(const QString& sessionId) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadFinalize", sessionId);
    return _result.value<LogosResult>();
}

void StorageModule::uploadFinalizeAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadFinalize", QVariantList() << sessionId, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::uploadCancel(const QString& sessionId) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "uploadCancel", sessionId);
    return _result.value<LogosResult>();
}

void StorageModule::uploadCancelAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "uploadCancel", QVariantList() << sessionId, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadCancel(const QString& sessionId) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadCancel", sessionId);
    return _result.value<LogosResult>();
}

void StorageModule::downloadCancelAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadCancel", QVariantList() << sessionId, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadToUrl(const QString& cid, QVariant url, bool local, int chunkSize) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadToUrl", cid, url, local, chunkSize);
    return _result.value<LogosResult>();
}

void StorageModule::downloadToUrlAsync(const QString& cid, QVariant url, bool local, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadToUrl", QVariantList{cid, url, local, chunkSize}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadToUrl(const QString& cid, QVariant url, bool local) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadToUrl", cid, url, local);
    return _result.value<LogosResult>();
}

void StorageModule::downloadToUrlAsync(const QString& cid, QVariant url, bool local, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadToUrl", QVariantList{cid, url, local}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadToUrl(const QString& cid, QVariant url) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadToUrl", cid, url);
    return _result.value<LogosResult>();
}

void StorageModule::downloadToUrlAsync(const QString& cid, QVariant url, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadToUrl", QVariantList{cid, url}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadChunks(const QString& cid, bool local, int chunkSize, const QString& filepath) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadChunks", cid, local, chunkSize, filepath);
    return _result.value<LogosResult>();
}

void StorageModule::downloadChunksAsync(const QString& cid, bool local, int chunkSize, const QString& filepath, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadChunks", QVariantList{cid, local, chunkSize, filepath}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadChunks(const QString& cid, bool local, int chunkSize) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadChunks", cid, local, chunkSize);
    return _result.value<LogosResult>();
}

void StorageModule::downloadChunksAsync(const QString& cid, bool local, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadChunks", QVariantList{cid, local, chunkSize}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadChunks(const QString& cid, bool local) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadChunks", cid, local);
    return _result.value<LogosResult>();
}

void StorageModule::downloadChunksAsync(const QString& cid, bool local, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadChunks", QVariantList{cid, local}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadChunks(const QString& cid) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadChunks", cid);
    return _result.value<LogosResult>();
}

void StorageModule::downloadChunksAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadChunks", QVariantList() << cid, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::exists(const QString& cid) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "exists", cid);
    return _result.value<LogosResult>();
}

void StorageModule::existsAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "exists", QVariantList() << cid, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::fetch(const QString& cid) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "fetch", cid);
    return _result.value<LogosResult>();
}

void StorageModule::fetchAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "fetch", QVariantList() << cid, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::remove(const QString& cid) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "remove", cid);
    return _result.value<LogosResult>();
}

void StorageModule::removeAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "remove", QVariantList() << cid, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::space() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "space");
    return _result.value<LogosResult>();
}

void StorageModule::spaceAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "space", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::manifests() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "manifests");
    return _result.value<LogosResult>();
}

void StorageModule::manifestsAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "manifests", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::downloadManifest(const QString& cid) {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "downloadManifest", cid);
    return _result.value<LogosResult>();
}

void StorageModule::downloadManifestAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "downloadManifest", QVariantList() << cid, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::stop() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "stop");
    return _result.value<LogosResult>();
}

void StorageModule::stopAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "stop", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult StorageModule::destroy() {
    QVariant _result = m_client->invokeRemoteMethod("storage_module", "destroy");
    return _result.value<LogosResult>();
}

void StorageModule::destroyAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "destroy", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

void StorageModule::importFiles(const QString& path) {
    m_client->invokeRemoteMethod("storage_module", "importFiles", path);
}

void StorageModule::importFilesAsync(const QString& path, std::function<void(void)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "importFiles", QVariantList() << path, [callback](QVariant v) {
        callback();
    }, timeout);
}

void StorageModule::initLogos(QVariant logosAPIInstance) {
    m_client->invokeRemoteMethod("storage_module", "initLogos", logosAPIInstance);
}

void StorageModule::initLogosAsync(QVariant logosAPIInstance, std::function<void(void)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("storage_module", "initLogos", QVariantList() << logosAPIInstance, [callback](QVariant v) {
        callback();
    }, timeout);
}

