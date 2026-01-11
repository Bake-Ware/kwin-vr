/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QQmlEngine>

class QAction;

namespace KWin
{

class KWinVrShortcuts : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static KWinVrShortcuts *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine)
    {
        Q_UNUSED(qmlEngine);
        Q_UNUSED(jsEngine);
        auto shortcuts = instance();
        QQmlEngine::setObjectOwnership(shortcuts, QQmlEngine::CppOwnership);
        return shortcuts;
    }

    static KWinVrShortcuts *instance();

Q_SIGNALS:
    void realignWindowTriggered();
    void grabWindowTriggered();
    void grabAllWindowsTriggered();
    void toggleHudTriggered();
    void testAction1Triggered();
    void testAction2Triggered();
    void toggleRayTriggered();
    void resetViewTriggered();

private:
    explicit KWinVrShortcuts(QObject *parent = nullptr);

    void registerShortcut(const QString &name, const QString &text,
                          const QKeySequence &defaultSequence,
                          void (KWinVrShortcuts::*signal)());
};

}
