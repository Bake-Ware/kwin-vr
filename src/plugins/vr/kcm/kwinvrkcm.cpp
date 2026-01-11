/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrkcm.h"

#include <KPluginFactory>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>

#include <algorithm>

namespace KWin
{

K_PLUGIN_CLASS_WITH_JSON(KwinVRKcm, "kwinvr_kcm.json")

KwinVRKcm::KwinVRKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickManagedConfigModule(parent, data)
    , m_data(new KwinVRConfigData(this))
{
    setButtons(Apply | Default);

    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kwinvr"),
        QStringLiteral("/KwinVr"),
        QStringLiteral("org.kde.kwinvr"),
        QStringLiteral("vrActiveChanged"),
        this,
        SIGNAL(vrActiveChanged()));
}

KWinVRConfig *KwinVRKcm::settings() const
{
    return m_data->settings();
}

bool KwinVRKcm::xrTest() const
{
    return m_xrTestProcess && m_xrTestProcess->state() == QProcess::Running;
}

void KwinVRKcm::setXrTest(bool running)
{
    if (running == xrTest()) {
        return;
    }

    if (!running) {
        if (m_xrTestProcess) {
            m_xrTestProcess->terminate();
        }
        return;
    }

    QString executable = QStandardPaths::findExecutable(
        QStringLiteral("kwinvr-xrtest"),
        {QCoreApplication::applicationDirPath(),
         QStringLiteral("/usr/libexec"),
         QStringLiteral("/usr/local/libexec")});

    if (executable.isEmpty()) {
        return;
    }

    if (!m_xrTestProcess) {
        m_xrTestProcess = new QProcess(this);
        connect(m_xrTestProcess, &QProcess::stateChanged, this, &KwinVRKcm::xrTestChanged);
    }

    m_xrTestProcess->start(executable, {});
}

QDBusInterface *KwinVRKcm::vrInterface() const
{
    if (!m_vrInterface) {
        m_vrInterface = new QDBusInterface(
            QStringLiteral("org.kde.kwinvr"),
            QStringLiteral("/KwinVr"),
            QStringLiteral("org.kde.kwinvr"),
            QDBusConnection::sessionBus(),
            const_cast<KwinVRKcm *>(this));
    }
    return m_vrInterface;
}

bool KwinVRKcm::vrActive() const
{
    auto iface = vrInterface();
    if (iface->isValid()) {
        return iface->property("vrActive").toBool();
    }
    return false;
}

void KwinVRKcm::setVrActive(bool active)
{
    auto iface = vrInterface();
    if (iface->isValid()) {
        iface->setProperty("vrActive", active);
    }
}

QStringList KwinVRKcm::openXrRuntimeCandidates() const
{
    return m_openXrRuntimeCandidates;
}

void KwinVRKcm::refreshOpenXrRuntimeCandidates()
{
    QStringList searchRoots;
    const QStringList dataLocations = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    for (const QString &location : dataLocations) {
        searchRoots.append(QDir(location).filePath(QStringLiteral("openxr/1")));
    }

    const QStringList configLocations = QStandardPaths::standardLocations(QStandardPaths::ConfigLocation);
    for (const QString &location : configLocations) {
        searchRoots.append(QDir(location).filePath(QStringLiteral("openxr/1")));
    }
    searchRoots.append(QStringLiteral("/etc/openxr/1"));

    QSet<QString> discoveredPaths;
    for (const QString &root : searchRoots) {
        const QFileInfo rootInfo(root);
        if (!rootInfo.exists() || !rootInfo.isDir()) {
            continue;
        }

        QDirIterator it(root, {QStringLiteral("*.json")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            const QFileInfo runtimeFile(path);
            const QString canonicalPath = runtimeFile.canonicalFilePath();
            if (!canonicalPath.isEmpty() && runtimeFile.isReadable()) {
                discoveredPaths.insert(canonicalPath);
            }
        }
    }

    QStringList candidates = discoveredPaths.values();
    std::sort(candidates.begin(), candidates.end());
    if (candidates == m_openXrRuntimeCandidates) {
        return;
    }

    m_openXrRuntimeCandidates = candidates;
    Q_EMIT openXrRuntimeCandidatesChanged();
}

} // namespace KWin

#include "kwinvrkcm.moc"
