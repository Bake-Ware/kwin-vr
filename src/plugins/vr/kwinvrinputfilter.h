/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVRINPUTFILTER_H
#define KWINVRINPUTFILTER_H

#pragma once

#include <QObject>
#include <QQuickItem>
#include <input.h>

namespace KWin
{
class KwinVrInputFilter : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QObject *eventsTarget READ eventsTarget WRITE setEventsTarget NOTIFY eventsTargetChanged FINAL)
    Q_PROPERTY(int pointerInhibitDelay READ pointerInhibitDelay WRITE setPointerInhibitDelay NOTIFY pointerInhibitDelayChanged FINAL)

    QML_ELEMENT
public:
    explicit KwinVrInputFilter(QObject *parent = nullptr);
    ~KwinVrInputFilter();

    QObject *eventsTarget() const;
    void setEventsTarget(QObject *newEventsTarget);

    int pointerInhibitDelay() const;
    void setPointerInhibitDelay(int newPointerInhibitDelay);

Q_SIGNALS:
    void eventsTargetChanged();
    void activeChanged();
    void pointerInhibitDelayChanged();

private:
    void resetEventsTarget();
    void updateInputFilter();

    InputEventFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};

}
#endif // VRINPUTFILTER_H
