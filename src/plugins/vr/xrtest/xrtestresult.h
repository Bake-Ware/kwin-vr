/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>

class XrTestResult : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString message READ message WRITE setMessage NOTIFY messageChanged FINAL)
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
