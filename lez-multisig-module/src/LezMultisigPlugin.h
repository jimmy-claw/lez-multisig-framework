#pragma once

#include <QObject>
#include <QWidget>
#include <QtPlugin>

class LogosAPI;
class LezMultisigBackend;

class IComponent {
public:
    virtual ~IComponent() = default;
    virtual QWidget* createWidget(LogosAPI* api = nullptr) = 0;
    virtual void     destroyWidget(QWidget* widget) = 0;
};
#define IComponent_iid "com.logos.component.IComponent"
Q_DECLARE_INTERFACE(IComponent, IComponent_iid)

class LezMultisigPlugin : public QObject, public IComponent {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID IComponent_iid FILE "../metadata.json")
    Q_INTERFACES(IComponent)

public:
    explicit LezMultisigPlugin(QObject* parent = nullptr);
    ~LezMultisigPlugin() override;

    Q_INVOKABLE void initLogos(LogosAPI* api);

    QWidget* createWidget(LogosAPI* api = nullptr) override;
    void     destroyWidget(QWidget* widget) override;

private:
    LogosAPI*           m_api     = nullptr;
    LezMultisigBackend* m_backend = nullptr;
};
