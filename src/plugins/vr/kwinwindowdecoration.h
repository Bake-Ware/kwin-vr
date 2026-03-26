/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationShadow>
#include <QQuickPaintedItem>

namespace KWin
{
class KwinWindowDecoration : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(KDecoration3::Decoration *decoration READ decoration WRITE setDecoration NOTIFY decorationChanged FINAL)
    Q_PROPERTY(KDecoration3::DecorationShadow *shadow READ shadow NOTIFY shadowChanged FINAL)

    QML_ELEMENT
public:
    explicit KwinWindowDecoration(QQuickItem *parent = nullptr);

    KDecoration3::Decoration *decoration() const;
    void setDecoration(KDecoration3::Decoration *newDecoration);

    KDecoration3::DecorationShadow *shadow() const;

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void decorationChanged();
    void shadowChanged();

private:
    void onDecorationDamaged(const QRegion &region);
    void onDecorationBordersChanged();
    void onDecorationDestroyed();

    KDecoration3::Decoration *m_decoration = nullptr;

    QRegion m_decoDamage;
};

} // namespace KWin
