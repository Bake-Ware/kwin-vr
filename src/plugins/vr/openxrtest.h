/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef OPENXRTEST_H
#define OPENXRTEST_H

#include <QObject>
#include <QProcess>

class OpenXRTest : public QObject
{
    Q_OBJECT

public:
    explicit OpenXRTest(QObject *parent = nullptr);
    ~OpenXRTest();

    void start();
    void stop();

Q_SIGNALS:
    void sessionResult(bool success, const QString &message);

private Q_SLOTS:
    void onReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);

private:
    void emitResult(bool success, const QString &message);

    QProcess *m_process = nullptr;
    bool m_resultEmitted = false;
};

#endif // OPENXRTEST_H
