/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrinputdevice.h"
#include "input.h"
#include <linux/input-event-codes.h>

using namespace KWin;
KwinVrInputDevice::KwinVrInputDevice(QObject *parent)
    : InputDevice{parent}
{
}

KwinVrInputDevice::~KwinVrInputDevice()
{
    if (m_active) {
        input()->removeInputDevice(this);
    }
}

QString KwinVrInputDevice::name() const
{
    return "KWin Vr Input Emulator";
}

bool KwinVrInputDevice::isEnabled() const
{
    return m_enabled;
}

void KwinVrInputDevice::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;

    m_enabled = enabled;
    Q_EMIT enabledChanged();
}

bool KwinVrInputDevice::enabled() const
{
    return m_enabled;
}

bool KwinVrInputDevice::isKeyboard() const
{
    return true;
}

bool KwinVrInputDevice::isPointer() const
{
    return true;
}

bool KwinVrInputDevice::isTouchpad() const
{
    return false;
}

bool KwinVrInputDevice::isTouch() const
{
    return false;
}

bool KwinVrInputDevice::isTabletTool() const
{
    return false;
}

bool KwinVrInputDevice::isTabletPad() const
{
    return false;
}

bool KwinVrInputDevice::isTabletModeSwitch() const
{
    return false;
}

bool KwinVrInputDevice::isLidSwitch() const
{
    return false;
}

bool KwinVrInputDevice::active() const
{
    return m_active;
}

void KwinVrInputDevice::setActive(bool newActive)
{
    if (m_active == newActive)
        return;
    m_active = newActive;

    if (newActive) {
        input()->addInputDevice(this);
    } else {
        input()->removeInputDevice(this);
    }
    Q_EMIT activeChanged();
}

QPointF KwinVrInputDevice::pointerPosition() const
{
    return m_pointerPosition;
}

#include "pointer_input.h"

void KwinVrInputDevice::setPointerPosition(QPointF newPointerPosition)
{
    if (m_pointerPosition == newPointerPosition)
        return;

    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());

    m_pointerPosition = newPointerPosition;

    //    qWarning() << "Moving pointer to " << newPointerPosition << " at " << micros.count() << " microseconds";

    Q_EMIT pointerMotionAbsolute(newPointerPosition, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT pointerPositionChanged();
}

bool KwinVrInputDevice::leftButton() const
{
    return m_leftButton;
}

void KwinVrInputDevice::setLeftButton(bool newLeftButton)
{
    if (m_leftButton == newLeftButton)
        return;
    m_leftButton = newLeftButton;
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    Q_EMIT pointerButtonChanged(BTN_LEFT, newLeftButton ? PointerButtonState::Pressed : PointerButtonState::Released, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT leftButtonChanged();
}

bool KwinVrInputDevice::middleButton() const
{
    return m_middleButton;
}

void KwinVrInputDevice::setMiddleButton(bool newMiddleButton)
{
    if (m_middleButton == newMiddleButton)
        return;
    m_middleButton = newMiddleButton;
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    Q_EMIT pointerButtonChanged(BTN_MIDDLE, newMiddleButton ? PointerButtonState::Pressed : PointerButtonState::Released, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT middleButtonChanged();
}

bool KwinVrInputDevice::rightButton() const
{
    return m_rightButton;
}

void KwinVrInputDevice::setRightButton(bool newRightButton)
{
    if (m_rightButton == newRightButton)
        return;
    m_rightButton = newRightButton;
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    Q_EMIT pointerButtonChanged(BTN_RIGHT, newRightButton ? PointerButtonState::Pressed : PointerButtonState::Released, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT rightButtonChanged();
}

bool KwinVrInputDevice::backButton() const
{
    return m_backButton;
}

void KwinVrInputDevice::setBackButton(bool newBackButton)
{
    if (m_backButton == newBackButton)
        return;
    m_backButton = newBackButton;
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    // BTN_SIDE is the standard code for Mouse Button 4 (Back)
    Q_EMIT pointerButtonChanged(BTN_SIDE, newBackButton ? PointerButtonState::Pressed : PointerButtonState::Released, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT backButtonChanged();
}

bool KwinVrInputDevice::forwardButton() const
{
    return m_forwardButton;
}

void KwinVrInputDevice::setForwardButton(bool newForwardButton)
{
    if (m_forwardButton == newForwardButton)
        return;
    m_forwardButton = newForwardButton;
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    // BTN_EXTRA is the standard code for Mouse Button 5 (Forward)
    Q_EMIT pointerButtonChanged(BTN_EXTRA, newForwardButton ? PointerButtonState::Pressed : PointerButtonState::Released, micros, this);
    Q_EMIT pointerFrame(this);
    Q_EMIT forwardButtonChanged();
}

void KwinVrInputDevice::setAxis(qreal vdelta, qreal hdelta)
{
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());

    if (vdelta) {
        Q_EMIT pointerAxisChanged(PointerAxis::Vertical, vdelta, 0, PointerAxisSource::Continuous, false, micros, this);
    }
    if (hdelta) {
        Q_EMIT pointerAxisChanged(PointerAxis::Horizontal, hdelta, 0, PointerAxisSource::Continuous, false, micros, this);
    }

    if (vdelta || hdelta) {
        Q_EMIT pointerFrame(this);
    }
}

void KwinVrInputDevice::sendKey(const QString &keyName, bool pressed)
{
    uint32_t code = 0;
    QString name = keyName;
    if (name.isEmpty())
        return;

    if (name.length() == 1) {
        QChar c = name.at(0).toUpper();
        if (c >= 'A' && c <= 'Z') {
            static const uint32_t letter_codes[] = {
                KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
                KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z};
            code = letter_codes[c.toLatin1() - 'A'];
        } else if (c >= '0' && c <= '9') {
            if (c == '0')
                code = KEY_0;
            else
                code = KEY_1 + (c.toLatin1() - '1');
        }
    }

    if (code == 0) {
        if (name == "Space")
            code = KEY_SPACE;
        else if (name == "Enter" || name == "Return")
            code = KEY_ENTER;
        else if (name == "Tab")
            code = KEY_TAB;
        else if (name == "BackSpace" || name == "Backspace")
            code = KEY_BACKSPACE;
        else if (name == "Escape" || name == "Esc")
            code = KEY_ESC;
        else if (name == "Shift")
            code = KEY_LEFTSHIFT;
        else if (name == "Control" || name == "Ctrl")
            code = KEY_LEFTCTRL;
        else if (name == "Alt")
            code = KEY_LEFTALT;
        else if (name == "Meta" || name == "Super")
            code = KEY_LEFTMETA;
        else if (name == "Left")
            code = KEY_LEFT;
        else if (name == "Right")
            code = KEY_RIGHT;
        else if (name == "Up")
            code = KEY_UP;
        else if (name == "Down")
            code = KEY_DOWN;
        else if (name == "Page Up")
            code = KEY_PAGEUP;
        else if (name == "Page Down")
            code = KEY_PAGEDOWN;
        else if (name == "Home")
            code = KEY_HOME;
        else if (name == "End")
            code = KEY_END;
        else if (name == "Insert")
            code = KEY_INSERT;
        else if (name == "Delete")
            code = KEY_DELETE;
        else if (name == "F1")
            code = KEY_F1;
        else if (name == "F2")
            code = KEY_F2;
        else if (name == "F3")
            code = KEY_F3;
        else if (name == "F4")
            code = KEY_F4;
        else if (name == "F5")
            code = KEY_F5;
        else if (name == "F6")
            code = KEY_F6;
        else if (name == "F7")
            code = KEY_F7;
        else if (name == "F8")
            code = KEY_F8;
        else if (name == "F9")
            code = KEY_F9;
        else if (name == "F10")
            code = KEY_F10;
        else if (name == "F11")
            code = KEY_F11;
        else if (name == "F12")
            code = KEY_F12;
    }

    if (code != 0) {
        auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch());
        Q_EMIT keyChanged(code, pressed ? KeyboardKeyState::Pressed : KeyboardKeyState::Released, micros, this);
    }
}
