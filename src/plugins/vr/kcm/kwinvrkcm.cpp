/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrkcm.h"

#include <KPluginFactory>
#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusVariant>
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

    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kwinvr"),
        QStringLiteral("/KwinVr"),
        QStringLiteral("org.kde.kwinvr"),
        QStringLiteral("leasableOutputsChanged"),
        this,
        SLOT(refreshLeasableOutputs()));
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

QVariantList KwinVRKcm::leasableOutputs() const
{
    return m_leasableOutputs;
}

static QVariantMap unwrapDBusMap(const QVariant &v)
{
    QVariantMap result;
    if (v.canConvert<QDBusArgument>()) {
        const auto arg = v.value<QDBusArgument>();
        arg.beginMap();
        while (!arg.atEnd()) {
            QString key;
            QDBusVariant val;
            arg.beginMapEntry();
            arg >> key >> val;
            arg.endMapEntry();
            result.insert(key, val.variant());
        }
        arg.endMap();
    }
    return result;
}

void KwinVRKcm::refreshLeasableOutputs()
{
    auto iface = vrInterface();
    if (!iface->isValid()) {
        return;
    }
    auto reply = iface->call(QStringLiteral("leasableOutputs"));
    if (reply.type() == QDBusMessage::ErrorMessage) {
        return;
    }
    auto args = reply.arguments();
    if (args.isEmpty()) {
        return;
    }

    QVariantList outputs;
    const auto outerArg = args.first().value<QDBusArgument>();
    outerArg.beginArray();
    while (!outerArg.atEnd()) {
        QVariant entry;
        outerArg >> entry;
        outputs.append(unwrapDBusMap(entry));
    }
    outerArg.endArray();

    if (m_leasableOutputs != outputs) {
        m_leasableOutputs = outputs;
        Q_EMIT leasableOutputsChanged();
    }
}

bool KwinVRKcm::setOutputLeasable(const QString &outputName, bool leasable)
{
    auto iface = vrInterface();
    if (!iface->isValid()) {
        return false;
    }
    auto reply = iface->call(QStringLiteral("setOutputLeasable"), outputName, leasable);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        return false;
    }
    return reply.arguments().value(0).toBool();
}

void KwinVRKcm::refreshLeases()
{
    auto iface = vrInterface();
    if (iface->isValid()) {
        iface->call(QStringLiteral("refreshLeases"));
    }
}

bool KwinVRKcm::isAutoLeaseOutput(const QString &name) const
{
    return m_data->settings()->autoLeaseOutputs().contains(name);
}

void KwinVRKcm::setAutoLeaseOutput(const QString &name, bool autoLease)
{
    QStringList list = m_data->settings()->autoLeaseOutputs();
    if (autoLease && !list.contains(name)) {
        list.append(name);
    } else if (!autoLease) {
        list.removeAll(name);
    }
    m_data->settings()->setAutoLeaseOutputs(list);
    settingsChanged();
}

} // namespace KWin

#include "kwinvrkcm.moc"
