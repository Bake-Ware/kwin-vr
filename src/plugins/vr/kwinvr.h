/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "openxrtest.h"
#include "plugin.h"

#include <KConfigWatcher>
#include <KNotification>

#include <QKeySequence>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QString>
#include <QVariantList>

namespace KWin
{

class KwinVr : public Plugin
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwinvr")
    Q_PROPERTY(bool vrActive READ vrActive WRITE setVrActive NOTIFY vrActiveChanged)
public:
    explicit KwinVr();
    ~KwinVr() override;

    bool vrActive() const;
    void setVrActive(bool active);

public Q_SLOTS:
    QVariantList leasableOutputs() const;
    bool setOutputLeasable(const QString &outputName, bool leasable);

Q_SIGNALS:
    void vrActiveChanged();
    void leasableOutputsChanged();

private:
    void onActivateVr(bool checked);

    void start();
    void stop();

    void showNotification(const QString &title, const QString &text,
                          KNotification::NotificationFlags flags);
    void closeNotification();

    void registerDBusService();
    bool initOpenXRLoaderWithRuntime(const QString &runtimeJsonPath, QString *errorMessage) const;
    void ensureMonadoRunning();
    void proceedWithVrActivation();

    bool m_active = false;
    bool m_waitingForMonado = false;
    QQmlApplicationEngine *m_engine = nullptr;
    OpenXRTest m_xrTest;
    KConfigWatcher::Ptr m_watcher;
    KNotification *m_notification = nullptr;
    bool m_openXRLoaderInitialized = false;
    QString m_openXRLoaderRuntimePath;
};

} // namespace KWin
