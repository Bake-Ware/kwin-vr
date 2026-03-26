/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrinputdevice.h"
#include "keyboard_input.h"
#include "pointer_input.h"
#include "xkb.h"

#include <QKeySequence>

#include <linux/input-event-codes.h>

namespace KWin
{

KwinVrInputDevice::KwinVrInputDevice(QObject *parent)
    : InputDevice{parent}
{
}

KwinVrInputDevice::~KwinVrInputDevice()
{
    if (m_active && input()) {
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
    if (m_enabled == enabled) {
        return;
    }

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
    if (m_active == newActive) {
        return;
    }
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

void KwinVrInputDevice::setPointerPosition(QPointF newPointerPosition)
{
    if (m_pointerPosition == newPointerPosition) {
        return;
    }

    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());

    m_pointerPosition = newPointerPosition;

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
    if (m_leftButton == newLeftButton) {
        return;
    }
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
    if (m_middleButton == newMiddleButton) {
        return;
    }
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
    if (m_rightButton == newRightButton) {
        return;
    }
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
    if (m_backButton == newBackButton) {
        return;
    }
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
    if (m_forwardButton == newForwardButton) {
        return;
    }
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

int KwinVrInputDevice::resolveKeyCode(const QString &keyName)
{
    if (keyName.isEmpty()) {
        return -1;
    }

    const auto sequence = QKeySequence::fromString(keyName);
    if (sequence.isEmpty()) {
        return -1;
    }

    const auto syms = Xkb::keysymsFromQtKey(sequence[0]);
    for (const auto sym : syms) {
        auto code = input()->keyboard()->xkb()->keycodeFromKeysym(sym);
        if (code) {
            return code->keyCode;
        }
    }
    return -1;
}

void KwinVrInputDevice::sendKeyCode(int code, bool pressed)
{
    if (code < 0) {
        return;
    }
    auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    Q_EMIT keyChanged(code, pressed ? KeyboardKeyState::Pressed : KeyboardKeyState::Released, micros, this);
}

void KwinVrInputDevice::sendKey(const QString &keyName, bool pressed)
{
    sendKeyCode(resolveKeyCode(keyName), pressed);
}

} // namespace KWin
