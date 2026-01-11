/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef XRTESTRESULT_H
#define XRTESTRESULT_H

#include <QGuiApplication>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTextStream>
#include <QTimer>

class XrTestResult : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString message READ message WRITE setMessage NOTIFY messageChanged)
public:
    using QObject::QObject;

    QString message() const;
    void setMessage(const QString &msg);

Q_SIGNALS:
    void messageChanged();

private:
    QString m_message;
    bool m_sent = false;
};

#endif // XRTESTRESULT_H
