// Standalone preview app — loads the QML UI without Basecamp.
// Build with: cmake -B build && cmake --build build
// Run with:   LEZ_MULTISIG_PROGRAM_ID_HEX=<hex> ./build/lez_multisig_app

#include "LezMultisigBackend.h"
#include "LezMultisigPlugin.h"

#include <QApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWidget>
#include <QUrl>
#include <cstdlib>

int main(int argc, char** argv) {
	QApplication app(argc, argv);
	app.setOrganizationName("logos-co");
	app.setApplicationName("lez_multisig");

	LezMultisigBackend backend(nullptr);

	QQuickWidget view;
	view.engine()->rootContext()->setContextProperty("backend", &backend);
	view.setResizeMode(QQuickWidget::SizeRootObjectToView);
	view.resize(900, 640);

	const char* qmlPath = std::getenv("QML_PATH");
	if (qmlPath)
		view.setSource(QUrl::fromLocalFile(QString::fromUtf8(qmlPath) + "/Main.qml"));
	else
		view.setSource(QUrl("qrc:/qml/Main.qml"));

	view.setWindowTitle("LezMultisig");
	view.show();
	return app.exec();
}
