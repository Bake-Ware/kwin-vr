/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "custodian.h"

#include <QCoreApplication>

#include <signal.h>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kwin-vr-custodian"));
    app.setOrganizationName(QStringLiteral("KDE"));

    // Handle SIGTERM/SIGHUP gracefully via the Qt event loop
    auto handleSignal = [](int) {
        QCoreApplication::quit();
    };
    ::signal(SIGTERM, handleSignal);
    ::signal(SIGINT, handleSignal);

    Custodian custodian;
    if (!custodian.start()) {
        return 1;
    }

    return app.exec();
}
