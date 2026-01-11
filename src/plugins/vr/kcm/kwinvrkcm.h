/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVRKCM_H
#define KWINVRKCM_H

#include <KQuickManagedConfigModule>

#include "kwinvrconfig.h"
#include "kwinvrconfigdata.h"

class QDBusInterface;
class QProcess;

namespace KWin
{

class KwinVRKcm : public KQuickManagedConfigModule
{
    Q_OBJECT
    Q_PROPERTY(KWin::KWinVRConfig *settings READ settings CONSTANT)
    Q_PROPERTY(bool xrTest READ xrTest WRITE setXrTest NOTIFY xrTestChanged)
    Q_PROPERTY(bool vrActive READ vrActive WRITE setVrActive NOTIFY vrActiveChanged)
    QML_ELEMENT
    QML_ANONYMOUS
public:
    KwinVRKcm(QObject *parent, const KPluginMetaData &data);

    KWinVRConfig *settings() const;

    bool xrTest() const;
    void setXrTest(bool running);

    bool vrActive() const;
    void setVrActive(bool active);

Q_SIGNALS:
    void xrTestChanged();
    void vrActiveChanged();

private:
    QDBusInterface *vrInterface() const;

    KwinVRConfigData *m_data;
    QProcess *m_xrTestProcess = nullptr;
    mutable QDBusInterface *m_vrInterface = nullptr;
};
}

#endif // KWINVRKCM_H
