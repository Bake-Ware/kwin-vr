/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QProcess>

namespace KWin
{

class OpenXRTest : public QObject
{
    Q_OBJECT

public:
    explicit OpenXRTest(QObject *parent = nullptr);
    ~OpenXRTest() override;

    void start();
    void stop();

Q_SIGNALS:
    void sessionResult(bool success, const QString &message);

private:
    void onReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);
    void emitResult(bool success, const QString &message);

    QProcess *m_process = nullptr;
    bool m_resultEmitted = false;
};

} // namespace KWin
