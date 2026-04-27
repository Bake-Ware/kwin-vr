/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone XR test application
// Launched by KWin VR plugin to test OpenXR availability

#include "xrtestresult.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QFileInfo>
#include <QGuiApplication>
#include <QLibrary>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTextStream>
#include <QTimer>

// NOLINTNEXTLINE(misc-include-cleaner)
#include <openxr/openxr.h>

static QString readOpenXrRuntimeJsonPath()
{
    const KConfigGroup generalGroup(KSharedConfig::openConfig(QStringLiteral("kwinvr")), QStringLiteral("General"));
    return generalGroup.readEntry(QStringLiteral("openXrRuntimeJson"), QString()).trimmed();
}

static bool initOpenXRLoaderWithRuntime(const QString &runtimeJsonPath, QString *errorMessage)
{
    const QFileInfo runtimeJsonInfo(runtimeJsonPath);
    if (!runtimeJsonInfo.isAbsolute()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("OpenXR runtime JSON path must be absolute");
        }
        return false;
    }

    if (!runtimeJsonInfo.exists()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("OpenXR runtime JSON does not exist: %1").arg(runtimeJsonPath);
        }
        return false;
    }

    QLibrary openXRLoader(QStringLiteral("openxr_loader"));
    if (!openXRLoader.load()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Failed to load OpenXR loader library: %1").arg(openXRLoader.errorString());
        }
        return false;
    }

    const auto pfnXrGetInstanceProcAddr = reinterpret_cast<PFN_xrGetInstanceProcAddr>(openXRLoader.resolve("xrGetInstanceProcAddr"));
    if (!pfnXrGetInstanceProcAddr) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrGetInstanceProcAddr not available in OpenXR loader");
        }
        return false;
    }

    PFN_xrInitializeLoaderKHR pfnInitializeLoaderKHR = nullptr;
    XrResult xr = pfnXrGetInstanceProcAddr(
        XR_NULL_HANDLE,
        "xrInitializeLoaderKHR",
        reinterpret_cast<PFN_xrVoidFunction *>(&pfnInitializeLoaderKHR));

    if (XR_FAILED(xr) || pfnInitializeLoaderKHR == nullptr) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrInitializeLoaderKHR not available (result=%1)").arg(xr);
        }
        return false;
    }

    const QByteArray runtimeJsonAbsPath = runtimeJsonInfo.absoluteFilePath().toUtf8();
    const XrLoaderInitPropertyValueEXT properties[] = {
        {"XR_RUNTIME_JSON", runtimeJsonAbsPath.constData()},
    };

    const XrLoaderInitInfoPropertiesEXT initProps{
        XR_TYPE_LOADER_INIT_INFO_PROPERTIES_EXT,
        nullptr,
        1,
        properties,
    };

    xr = pfnInitializeLoaderKHR(reinterpret_cast<const XrLoaderInitInfoBaseHeaderKHR *>(&initProps));
    if (XR_FAILED(xr)) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("xrInitializeLoaderKHR failed with result=%1").arg(xr);
        }
        return false;
    }

    return true;
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kwinvr-xrtest"));

    const QString runtimeJsonPath = readOpenXrRuntimeJsonPath();
    if (!runtimeJsonPath.isEmpty()) {
        QString initError;
        if (!initOpenXRLoaderWithRuntime(runtimeJsonPath, &initError)) {
            QTextStream(stdout) << "OpenXR loader init failed: " << initError << Qt::endl;
            return 1;
        }
    }

    const KConfigGroup generalGroup(KSharedConfig::openConfig(QStringLiteral("kwinvr")), QStringLiteral("General"));
    qputenv("QT_QUICK3D_XR_ASYNC_RENDER", generalGroup.readEntry("threadedRendering", false) ? "1" : "0");

    bool multiviewEnabled = generalGroup.readEntry("multiview", false);
    if (multiviewEnabled && QFileInfo::exists(QStringLiteral("/sys/module/nvidia"))) {
        multiviewEnabled = false;
    }
    qputenv("QT_QUICK3D_XR_DISABLE_MULTIVIEW", multiviewEnabled ? "0" : "1");

    QQmlApplicationEngine engine;
    XrTestResult result;
    engine.rootContext()->setContextProperty(QStringLiteral("xrTestResult"), &result);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [&](QObject *obj, const QUrl &) {
        if (!obj) {
            result.setMessage(QStringLiteral("Failed to create XR test scene"));
        }
    });
    engine.load(QStringLiteral("qrc:/xrtest/XrTest.qml"));

    if (engine.rootObjects().isEmpty()) {
        result.setMessage(QStringLiteral("Failed to load XR test QML"));
        return 1;
    }

    return app.exec();
}
