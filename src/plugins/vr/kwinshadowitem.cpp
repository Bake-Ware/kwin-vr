/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinshadowitem.h"

#include <QPainter>

namespace KWin
{

KwinShadowItem::KwinShadowItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setOpaquePainting(false);
}

KDecoration3::DecorationShadow *KwinShadowItem::shadow() const
{
    return m_shadow;
}

void KwinShadowItem::setShadow(KDecoration3::DecorationShadow *shadow)
{
    if (m_shadow == shadow) {
        return;
    }

    if (m_shadow) {
        disconnect(m_shadow, nullptr, this, nullptr);
    }

    m_shadow = shadow;

    if (m_shadow) {
        connect(m_shadow, &KDecoration3::DecorationShadow::shadowChanged, this, &KwinShadowItem::updateShadow);
        connect(m_shadow, &KDecoration3::DecorationShadow::paddingChanged, this, &KwinShadowItem::updateShadow);
        connect(m_shadow, &KDecoration3::DecorationShadow::innerShadowRectChanged, this, &KwinShadowItem::updateShadow);
        connect(m_shadow, &QObject::destroyed, this, [this] {
            m_shadow = nullptr;
            updateShadow();
            Q_EMIT shadowChanged();
        });
    }

    updateShadow();
    Q_EMIT shadowChanged();
}

bool KwinShadowItem::debug() const
{
    return m_debug;
}

void KwinShadowItem::setDebug(bool newDebug)
{
    if (m_debug == newDebug) {
        return;
    }
    m_debug = newDebug;
    update();
    Q_EMIT debugChanged();
}

void KwinShadowItem::updateShadow()
{
    if (m_shadow && !m_shadow->shadow().isNull()) {
        QImage img = m_shadow->shadow();
        setImplicitSize(img.width(), img.height());
    } else {
        setImplicitSize(1, 1);
    }
    update();
}

void KwinShadowItem::paint(QPainter *painter)
{
    if (!m_shadow) {
        return;
    }
    QImage img = m_shadow->shadow();
    if (img.isNull()) {
        return;
    }

    if (m_debug) {
        painter->fillRect(QRect(0, 0, img.width(), img.height()), Qt::magenta);
    } else {
        painter->drawImage(0, 0, img);
    }
}

} // namespace KWin
