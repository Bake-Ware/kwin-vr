/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinwindowdecoration.h"
#include "kwinvr_logging.h"

#include <KDecoration3/DecoratedWindow>

namespace KWin
{

KwinWindowDecoration::KwinWindowDecoration(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
}

KDecoration3::Decoration *KwinWindowDecoration::decoration() const
{
    return m_decoration;
}

KDecoration3::DecorationShadow *KwinWindowDecoration::shadow() const
{
    if (!m_decoration) {
        return nullptr;
    }
    return m_decoration->shadow().get();
}

void KwinWindowDecoration::setDecoration(KDecoration3::Decoration *newDecoration)
{
    if (m_decoration == newDecoration) {
        return;
    }

    if (m_decoration) {
        disconnect(m_decoration, &KDecoration3::Decoration::damaged, this, &KwinWindowDecoration::onDecorationDamaged);
        disconnect(m_decoration, &KDecoration3::Decoration::bordersChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
        disconnect(m_decoration, &KDecoration3::Decoration::resizeOnlyBordersChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
        disconnect(m_decoration, &KDecoration3::Decoration::shadowChanged, this, &KwinWindowDecoration::shadowChanged);
        disconnect(m_decoration, &KDecoration3::Decoration::destroyed, this, &KwinWindowDecoration::onDecorationDestroyed);

        auto window = m_decoration->window();
        if (window) {
            disconnect(window, &KDecoration3::DecoratedWindow::sizeChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
        }
    }

    m_decoration = newDecoration;

    m_decoDamage = {};

    if (m_decoration) {
        connect(m_decoration, &KDecoration3::Decoration::damaged, this, &KwinWindowDecoration::onDecorationDamaged);
        connect(m_decoration, &KDecoration3::Decoration::bordersChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
        connect(m_decoration, &KDecoration3::Decoration::resizeOnlyBordersChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
        connect(m_decoration, &KDecoration3::Decoration::shadowChanged, this, &KwinWindowDecoration::shadowChanged);
        connect(m_decoration, &KDecoration3::Decoration::destroyed, this, &KwinWindowDecoration::onDecorationDestroyed);

        auto window = m_decoration->window();
        if (window) {
            connect(window, &KDecoration3::DecoratedWindow::sizeChanged, this, &KwinWindowDecoration::onDecorationBordersChanged);
            connect(window, &QObject::destroyed, this, &KwinWindowDecoration::onDecorationDestroyed);
        } else {
            qCWarning(KWINVR) << "Decoration has no window, how is that possible?";
        }

        auto sz = m_decoration->size();
        m_decoDamage = QRect(0, 0, sz.width(), sz.height());
        setImplicitSize(sz.width(), sz.height());
    } else {
        setImplicitSize(1, 1);
    }

    update();

    Q_EMIT decorationChanged();
    Q_EMIT shadowChanged();
}

void KwinWindowDecoration::paint(QPainter *painter)
{
    if (!m_decoration) {
        return;
    }

    if (m_decoration->size().isEmpty()) {
        return;
    }

    auto r = m_decoDamage.boundingRect();
    m_decoDamage = {};
    m_decoration->paint(painter, r);
}

void KwinWindowDecoration::onDecorationDamaged(const QRegion &region)
{
    auto sz = m_decoration->size();
    setImplicitSize(sz.width(), sz.height());
    m_decoDamage += region;
    update();
}

void KwinWindowDecoration::onDecorationDestroyed()
{
    m_decoration = nullptr;
    Q_EMIT decorationChanged();
    setImplicitSize(1, 1);
    m_decoDamage = {};
    update();
}

void KwinWindowDecoration::onDecorationBordersChanged()
{
    auto sz = m_decoration->size();
    m_decoDamage = QRect(0, 0, sz.width(), sz.height());
    setImplicitSize(sz.width(), sz.height());
    update();
    Q_EMIT decorationChanged();
}

} // namespace KWin
