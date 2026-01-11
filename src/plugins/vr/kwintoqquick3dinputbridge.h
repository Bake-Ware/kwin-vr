/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QPointF>
#include <QQmlApplicationEngine>
#include <QQuickItem>

namespace KWin
{
class KWinToQQuick3DFilter;
class KWinToQQuick3DInputBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged FINAL)
    Q_PROPERTY(QPointF pointerPosition READ pointerPosition WRITE setPointerPosition NOTIFY pointerPositionChanged FINAL)

    QML_ELEMENT
public:
    explicit KWinToQQuick3DInputBridge(QObject *parent = nullptr);
    ~KWinToQQuick3DInputBridge() override;

    QQuickItem *target() const;
    void setTarget(QQuickItem *newTarget);

    QPointF pointerPosition() const;
    void setPointerPosition(QPointF newSetPointerPosition);

Q_SIGNALS:
    void targetChanged();
    void pointerPositionChanged();

private:
    void updateInputFilter();

    KWinToQQuick3DFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};

} // namespace KWin
