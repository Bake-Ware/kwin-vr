/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "input.h"

#include <QObject>
#include <QQmlEngine>

namespace KWin
{

class KwinVrInputDevice : public InputDevice
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged FINAL)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(QPointF pointerPosition READ pointerPosition WRITE setPointerPosition NOTIFY pointerPositionChanged FINAL)

    Q_PROPERTY(bool leftButton READ leftButton WRITE setLeftButton NOTIFY leftButtonChanged FINAL)
    Q_PROPERTY(bool middleButton READ middleButton WRITE setMiddleButton NOTIFY middleButtonChanged FINAL)
    Q_PROPERTY(bool rightButton READ rightButton WRITE setRightButton NOTIFY rightButtonChanged FINAL)
    Q_PROPERTY(bool backButton READ backButton WRITE setBackButton NOTIFY backButtonChanged FINAL)
    Q_PROPERTY(bool forwardButton READ forwardButton WRITE setForwardButton NOTIFY forwardButtonChanged FINAL)

    QML_ELEMENT
public:
    explicit KwinVrInputDevice(QObject *parent = nullptr);
    ~KwinVrInputDevice() override;

    QString name() const override;
    bool isEnabled() const override;
    void setEnabled(bool enabled) override;

private:
    bool enabled() const;

public:
    bool isKeyboard() const override;
    bool isPointer() const override;
    bool isTouchpad() const override;
    bool isTouch() const override;
    bool isTabletTool() const override;
    bool isTabletPad() const override;
    bool isTabletModeSwitch() const override;
    bool isLidSwitch() const override;

    bool active() const;
    void setActive(bool newActivate);

    QPointF pointerPosition() const;
    void setPointerPosition(QPointF newPointerPosition);

    bool leftButton() const;
    void setLeftButton(bool newLeftButton);

    bool middleButton() const;
    void setMiddleButton(bool newMiddleButton);

    bool rightButton() const;
    void setRightButton(bool newRightButton);

    bool backButton() const;
    void setBackButton(bool newBackButton);

    bool forwardButton() const;
    void setForwardButton(bool newForwardButton);

    Q_INVOKABLE void setAxis(qreal vdelta, qreal hdelta);
    Q_INVOKABLE int resolveKeyCode(const QString &keyName);
    Q_INVOKABLE void sendKeyCode(int code, bool pressed);
    Q_INVOKABLE void sendKey(const QString &keyName, bool pressed);

Q_SIGNALS:
    void enabledChanged();
    void activeChanged();
    void pointerPositionChanged();
    void leftButtonChanged();
    void middleButtonChanged();
    void rightButtonChanged();
    void backButtonChanged();
    void forwardButtonChanged();

private:
    bool m_enabled = true;
    bool m_active = false;
    QPointF m_pointerPosition;
    bool m_leftButton = false;
    bool m_middleButton = false;
    bool m_rightButton = false;
    bool m_backButton = false;
    bool m_forwardButton = false;
};

} // namespace KWin
