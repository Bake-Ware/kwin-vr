/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "openxrtest.h"
#include "kwinvr_logging.h"

#include <QCoreApplication>
#include <QStandardPaths>

namespace KWin
{

OpenXRTest::OpenXRTest(QObject *parent)
    : QObject(parent)
{
}

OpenXRTest::~OpenXRTest()
{
    stop();
}

void OpenXRTest::start()
{
    if (m_process) {
        return;
    }

    m_resultEmitted = false;
    m_process = new QProcess(this);

    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &OpenXRTest::onReadyRead);
    connect(m_process, &QProcess::finished,
            this, &OpenXRTest::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred,
            this, &OpenXRTest::onProcessError);

    // Will it be good to use only KDE_INSTALL_FULL_LIBEXECDIR ?
    QString executable = QStandardPaths::findExecutable(
        QStringLiteral("kwinvr-xrtest"),
        {QCoreApplication::applicationDirPath(),
         QStringLiteral("/usr/libexec"),
         QStringLiteral("/usr/local/libexec")});

    if (executable.isEmpty()) {
        executable = QStringLiteral(KDE_INSTALL_FULL_LIBEXECDIR "/kwinvr-xrtest");
    }

    qCDebug(KWINVR) << "Starting XR test:" << executable;
    m_process->start(executable, {});
}

void OpenXRTest::emitResult(bool success, const QString &message)
{
    if (m_resultEmitted) {
        return;
    }
    m_resultEmitted = true;
    Q_EMIT sessionResult(success, message);
}

void OpenXRTest::stop()
{
    if (!m_process) {
        return;
    }

    disconnect(m_process, nullptr, this, nullptr);

    if (m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
        if (!m_process->waitForFinished(1000)) {
            m_process->kill();
            m_process->waitForFinished(1000);
        }
    }

    m_process->deleteLater();
    m_process = nullptr;
}

void OpenXRTest::onReadyRead()
{
    if (!m_process) {
        return;
    }

    QString output = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
    qCDebug(KWINVR) << "XR test output:" << output;

    if (output.isEmpty()) {
        return;
    }

    bool success = (output == QStringLiteral("OK"));

    if (success) {
        emitResult(true, QStringLiteral("OpenXR test passed"));
    } else {
        emitResult(false, output);
    }
}

void OpenXRTest::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    qCDebug(KWINVR) << "XR test finished, exit code:" << exitCode;

    // Read any remaining output
    QString output = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
    QString errorOutput = QString::fromUtf8(m_process->readAllStandardError()).trimmed();

    m_process->deleteLater();
    m_process = nullptr;

    if (exitStatus == QProcess::CrashExit) {
        emitResult(false, QStringLiteral("XR test crashed"));
    } else if (exitCode != 0) {
        QString message = output.isEmpty() ? errorOutput : output;
        if (message.isEmpty()) {
            message = QStringLiteral("OpenXR test failed with exit code %1").arg(exitCode);
        }
        emitResult(false, message);
    }
}

void OpenXRTest::onProcessError(QProcess::ProcessError error)
{
    QString message;
    switch (error) {
    case QProcess::FailedToStart:
        message = QStringLiteral("Failed to start XR test executable");
        break;
    case QProcess::Crashed:
        message = QStringLiteral("XR test crashed");
        break;
    case QProcess::Timedout:
        message = QStringLiteral("XR test timed out");
        break;
    default:
        message = QStringLiteral("XR test error: %1").arg(error);
        break;
    }

    qCWarning(KWINVR) << message;

    if (m_process) {
        m_process->deleteLater();
        m_process = nullptr;
    }

    emitResult(false, message);
}

} // namespace KWin
