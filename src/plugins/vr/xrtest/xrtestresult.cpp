/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "xrtestresult.h"

QString XrTestResult::message() const
{
    return m_message;
}

void XrTestResult::setMessage(const QString &msg)
{
    if (m_sent)
        return;
    m_sent = true;
    m_message = msg;
    Q_EMIT messageChanged();

    QTextStream out(stdout);
    out << msg << Qt::endl;
    out.flush();

    if (msg != QStringLiteral("OK")) {
        QCoreApplication::exit(1);
    }
}
