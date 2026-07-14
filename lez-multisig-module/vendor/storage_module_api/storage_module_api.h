#pragma once
#include <QString>
#include <QVariant>
#include <QStringList>
#include <QJsonArray>
#include <QVariantList>
#include <QVariantMap>
#include <functional>
#include <utility>
#include "logos_types.h"
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_object.h"

class StorageModule {
public:
    explicit StorageModule(LogosAPI* api);

    using RawEventCallback = std::function<void(const QString&, const QVariantList&)>;
    using EventCallback = std::function<void(const QVariantList&)>;

    bool on(const QString& eventName, RawEventCallback callback);
    bool on(const QString& eventName, EventCallback callback);
    void setEventSource(LogosObject* source);
    LogosObject* eventSource() const;
    void trigger(const QString& eventName);
    void trigger(const QString& eventName, const QVariantList& data);
    template<typename... Args>
    void trigger(const QString& eventName, Args&&... args) {
        trigger(eventName, packVariantList(std::forward<Args>(args)...));
    }
    void trigger(const QString& eventName, LogosObject* source, const QVariantList& data);
    template<typename... Args>
    void trigger(const QString& eventName, LogosObject* source, Args&&... args) {
        trigger(eventName, source, packVariantList(std::forward<Args>(args)...));
    }

    bool init(const QString& cfg);
    void initAsync(const QString& cfg, std::function<void(bool)> callback, Timeout timeout = Timeout());
    bool start();
    void startAsync(std::function<void(bool)> callback, Timeout timeout = Timeout());
    LogosResult version();
    void versionAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult dataDir();
    void dataDirAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult peerId();
    void peerIdAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult debug();
    void debugAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult spr();
    void sprAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult updateLogLevel(const QString& logLevel);
    void updateLogLevelAsync(const QString& logLevel, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult connect(const QString& peerId, const QStringList& peerAddresses);
    void connectAsync(const QString& peerId, const QStringList& peerAddresses, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadUrl(QVariant url, int chunkSize);
    void uploadUrlAsync(QVariant url, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadUrl(QVariant url);
    void uploadUrlAsync(QVariant url, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadInit(const QString& filename, int chunkSize);
    void uploadInitAsync(const QString& filename, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadInit(const QString& filename);
    void uploadInitAsync(const QString& filename, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadChunk(const QString& sessionId, QVariant chunk);
    void uploadChunkAsync(const QString& sessionId, QVariant chunk, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadFinalize(const QString& sessionId);
    void uploadFinalizeAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult uploadCancel(const QString& sessionId);
    void uploadCancelAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadCancel(const QString& sessionId);
    void downloadCancelAsync(const QString& sessionId, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadToUrl(const QString& cid, QVariant url, bool local, int chunkSize);
    void downloadToUrlAsync(const QString& cid, QVariant url, bool local, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadToUrl(const QString& cid, QVariant url, bool local);
    void downloadToUrlAsync(const QString& cid, QVariant url, bool local, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadToUrl(const QString& cid, QVariant url);
    void downloadToUrlAsync(const QString& cid, QVariant url, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadChunks(const QString& cid, bool local, int chunkSize, const QString& filepath);
    void downloadChunksAsync(const QString& cid, bool local, int chunkSize, const QString& filepath, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadChunks(const QString& cid, bool local, int chunkSize);
    void downloadChunksAsync(const QString& cid, bool local, int chunkSize, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadChunks(const QString& cid, bool local);
    void downloadChunksAsync(const QString& cid, bool local, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadChunks(const QString& cid);
    void downloadChunksAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult exists(const QString& cid);
    void existsAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult fetch(const QString& cid);
    void fetchAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult remove(const QString& cid);
    void removeAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult space();
    void spaceAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult manifests();
    void manifestsAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult downloadManifest(const QString& cid);
    void downloadManifestAsync(const QString& cid, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult stop();
    void stopAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult destroy();
    void destroyAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    void importFiles(const QString& path);
    void importFilesAsync(const QString& path, std::function<void()> callback, Timeout timeout = Timeout());
    void initLogos(QVariant logosAPIInstance);
    void initLogosAsync(QVariant logosAPIInstance, std::function<void()> callback, Timeout timeout = Timeout());

private:
    LogosObject* ensureReplica();
    template<typename... Args>
    static QVariantList packVariantList(Args&&... args) {
        QVariantList list;
        list.reserve(sizeof...(Args));
        using Expander = int[];
        (void)Expander{0, (list.append(QVariant::fromValue(std::forward<Args>(args))), 0)...};
        return list;
    }
    LogosAPI* m_api;
    LogosAPIClient* m_client;
    QString m_moduleName;
    LogosObject* m_eventReplica = nullptr;
    LogosObject* m_eventSource = nullptr;
};
