/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QPointer>
#include <QtQmlIntegration/qqmlintegration.h>

namespace KWin
{
class Window;

class KwinVrHoveredWindowResolver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(KWin::Window *hoveredWindow READ hoveredWindow WRITE setHoveredWindow NOTIFY hoveredWindowChanged FINAL)
    QML_ELEMENT

public:
    explicit KwinVrHoveredWindowResolver(QObject *parent = nullptr);
    ~KwinVrHoveredWindowResolver() override;

    Window *hoveredWindow() const;
    void setHoveredWindow(Window *window);

Q_SIGNALS:
    void hoveredWindowChanged();

private:
    QPointer<Window> m_hoveredWindow;
};
} // namespace KWin
