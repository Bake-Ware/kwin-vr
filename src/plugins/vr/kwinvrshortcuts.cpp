/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrshortcuts.h"

#include <KGlobalAccel>
#include <KLocalizedString>

#include <QAction>

using namespace KWin;

KWinVrShortcuts *KWinVrShortcuts::instance()
{
    static KWinVrShortcuts *s_instance = new KWinVrShortcuts();
    return s_instance;
}

KWinVrShortcuts::KWinVrShortcuts(QObject *parent)
    : QObject(parent)
{
    registerShortcut(QStringLiteral("Realign VR Window"),
                     i18nc("@action Realign VR Window", "Realign VR Window"),
                     {Qt::CTRL | Qt::META | Qt::Key_W},
                     &KWinVrShortcuts::realignWindowTriggered);

    registerShortcut(QStringLiteral("Grab Window"),
                     i18nc("@action Grab Window", "Grab Window"),
                     {Qt::CTRL | Qt::META | Qt::Key_E},
                     &KWinVrShortcuts::grabWindowTriggered);

    registerShortcut(QStringLiteral("Grab All Windows"),
                     i18nc("@action Grab All Windows", "Grab All Windows"),
                     {Qt::SHIFT | Qt::META | Qt::Key_E},
                     &KWinVrShortcuts::grabAllWindowsTriggered);

    registerShortcut(QStringLiteral("VR Hud"),
                     i18nc("@action VR Hud", "VR Hud"),
                     {Qt::CTRL | Qt::META | Qt::Key_H},
                     &KWinVrShortcuts::toggleHudTriggered);

    registerShortcut(QStringLiteral("VR Test Action 1"),
                     i18nc("@action VR Test Action 1", "VR Test Action 1"),
                     {Qt::CTRL | Qt::META | Qt::Key_K},
                     &KWinVrShortcuts::testAction1Triggered);

    registerShortcut(QStringLiteral("VR Test Action 2"),
                     i18nc("@action VR Test Action 2", "VR Test Action 2"),
                     {Qt::CTRL | Qt::META | Qt::Key_L},
                     &KWinVrShortcuts::testAction2Triggered);

    registerShortcut(QStringLiteral("Disable VR Ray"),
                     i18nc("@action Disable VR Ray", "Disable VR Ray"),
                     {Qt::CTRL | Qt::META | Qt::Key_I},
                     &KWinVrShortcuts::toggleRayTriggered);

    registerShortcut(QStringLiteral("Reset View"),
                     i18nc("@action Reset View", "Reset View"),
                     {Qt::CTRL | Qt::META | Qt::Key_T},
                     &KWinVrShortcuts::resetViewTriggered);

    registerShortcut(QStringLiteral("Toggle PIP Window"),
                     i18nc("@action Toggle PIP Window", "Toggle PIP Window"),
                     {Qt::CTRL | Qt::META | Qt::Key_P},
                     &KWinVrShortcuts::togglePipTriggered);

    registerShortcut(QStringLiteral("Open Radial Menu"),
                     i18nc("@action Open Radial Menu", "Open Radial Menu"),
                     {Qt::CTRL | Qt::META | Qt::Key_R},
                     &KWinVrShortcuts::openRadialMenuTriggered);
}

void KWinVrShortcuts::registerShortcut(const QString &name, const QString &text,
                                       const QKeySequence &defaultSequence,
                                       void (KWinVrShortcuts::*signal)())
{
    auto action = new QAction(this);
    action->setObjectName(name);
    action->setText(text);
    action->setProperty("componentName", QStringLiteral("kwinvr"));
    action->setProperty("componentDisplayName", i18nc("@title shortcut component", "VR Interface"));
    KGlobalAccel::self()->setDefaultShortcut(action, {defaultSequence});
    KGlobalAccel::self()->setShortcut(action, {defaultSequence});
    connect(action, &QAction::triggered, this, signal);
}
