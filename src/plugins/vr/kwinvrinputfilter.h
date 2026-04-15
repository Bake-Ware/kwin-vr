/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "input.h"

#include <QObject>
#include <QQuickItem>

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
    ~KwinVrInputFilter() override;

    QObject *eventsTarget() const;
    void setEventsTarget(QObject *newEventsTarget);

    int pointerInhibitDelay() const;
    void setPointerInhibitDelay(int newPointerInhibitDelay);

Q_SIGNALS:
    void eventsTargetChanged();
    void activeChanged();
    void pointerInhibitDelayChanged();
    void pinchStarted(int fingerCount);
    void pinchUpdated(qreal scale, qreal angleDelta);
    void pinchEnded();
    void pinchCancelled();

private:
    void resetEventsTarget();
    void updateInputFilter();

    InputEventFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};

} // namespace KWin
