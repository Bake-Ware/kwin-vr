/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QSet>

namespace KWin
{

class Window;

/*
 * Registry of windows pinned to the HUD plane ("PIP"). Shared between the
 * window-model filters (a pinned window leaves the primary world plane and
 * is accepted by the HUD filter) and the QML scene (pinned windows render
 * scaled on the HUD).
 */
class VrPinRegistry : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    /* Bumped on every change; bind through it to re-evaluate isPinned(). */
    Q_PROPERTY(int revision READ revision NOTIFY pinnedChanged)

public:
    static VrPinRegistry *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
    {
        Q_UNUSED(qmlEngine);
        Q_UNUSED(jsEngine);
        auto registry = instance();
        QQmlEngine::setObjectOwnership(registry, QQmlEngine::CppOwnership);
        return registry;
    }

    static VrPinRegistry *instance();

    int revision() const
    {
        return m_revision;
    }

    Q_INVOKABLE bool isPinned(KWin::Window *window) const;
    Q_INVOKABLE void toggle(KWin::Window *window);

Q_SIGNALS:
    void pinnedChanged();

private:
    explicit VrPinRegistry(QObject *parent = nullptr);

    QSet<Window *> m_pinned;
    int m_revision = 0;
};

} // namespace KWin
