/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone XR test application
// Launched by KWin VR plugin to test OpenXR availability

#include "xrtestresult.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTextStream>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("kwinvr-xrtest");

    QQmlApplicationEngine engine;
    XrTestResult result;
    engine.rootContext()->setContextProperty("xrTestResult", &result);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [&](QObject *obj, const QUrl &) {
        if (!obj) {
            result.setMessage("Failed to create XR test scene");
        }
    });
    engine.load("qrc:/xrtest/XrTest.qml");

    if (engine.rootObjects().isEmpty()) {
        result.setMessage("Failed to load XR test QML");
        return 1;
    }

    return app.exec();
}
