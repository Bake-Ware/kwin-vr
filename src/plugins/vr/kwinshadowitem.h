/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KDecoration3/DecorationShadow>
#include <QDebug>
#include <QPainter>
#include <QQuickPaintedItem>

namespace KWin
{

class KwinShadowItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(KDecoration3::DecorationShadow *shadow READ shadow WRITE setShadow NOTIFY shadowChanged)
    /**
     * Fills shadow with magneta color to make it visible.
     */
    Q_PROPERTY(bool debug READ debug WRITE setDebug NOTIFY debugChanged)
    QML_ELEMENT
public:
    explicit KwinShadowItem(QQuickItem *parent = nullptr);

    KDecoration3::DecorationShadow *shadow() const;
    void setShadow(KDecoration3::DecorationShadow *shadow);

    bool debug() const;
    void setDebug(bool d);

    void updateShadow();

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void shadowChanged();
    void debugChanged();

private:
    KDecoration3::DecorationShadow *m_shadow = nullptr;
    bool m_debug = false;
};

}
