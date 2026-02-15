/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QQmlEngine>

namespace KWin
{
class InputDevice;
class InputEventSpy;

/**
 * Captures pointer motion deltas from external (non-VR) input devices
 * and accumulates them as angular offsets (in degrees).
 *
 * Uses InputEventSpy so it sees ALL pointer events before filters block them.
 * RelativeMotionBlocker still blocks the events from moving the KWin pointer;
 * this component just records the deltas for use as headgaze ray offset.
 */
class VrPointerOffset : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged FINAL)
    Q_PROPERTY(KWin::InputDevice *vrDevice READ vrDevice WRITE setVrDevice NOTIFY vrDeviceChanged FINAL)
    Q_PROPERTY(float offsetX READ offsetX NOTIFY offsetChanged FINAL)
    Q_PROPERTY(float offsetY READ offsetY NOTIFY offsetChanged FINAL)
    Q_PROPERTY(float sensitivity READ sensitivity WRITE setSensitivity NOTIFY sensitivityChanged FINAL)
    Q_PROPERTY(float maxOffset READ maxOffset WRITE setMaxOffset NOTIFY maxOffsetChanged FINAL)

public:
    explicit VrPointerOffset(QObject *parent = nullptr);
    ~VrPointerOffset();

    bool enabled() const;
    void setEnabled(bool newEnabled);

    KWin::InputDevice *vrDevice() const;
    void setVrDevice(KWin::InputDevice *newVrDevice);

    float offsetX() const;
    float offsetY() const;

    float sensitivity() const;
    void setSensitivity(float newSensitivity);

    float maxOffset() const;
    void setMaxOffset(float newMaxOffset);

    Q_INVOKABLE void reset();

Q_SIGNALS:
    void enabledChanged();
    void vrDeviceChanged();
    void offsetChanged();
    void sensitivityChanged();
    void maxOffsetChanged();

private:
    void updateSpy();
    void resetVrDevice();

    InputEventSpy *m_spy = nullptr;
    bool m_spyInstalled = false;
    bool m_enabled = false;
    float m_offsetX = 0.0f;
    float m_offsetY = 0.0f;
    float m_sensitivity = 0.1f;
    float m_maxOffset = 20.0f;
};

} // namespace KWin
