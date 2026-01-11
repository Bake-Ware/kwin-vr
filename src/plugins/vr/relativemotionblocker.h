/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QQmlEngine>

/**
 * Blocks all pointer motion events from KWin when the input is not constrained,
 * except from the allowed device.
 *
 * When VR mode is active the head ray is the only input source, so any pointer movement
 * from other input devices will not be passed further.
 *
 * However, when the pointer is constrained (i.e. a game requested pointer lock)
 * all events will be passed further, so you can play Half Life with your mouse as expected.
 */
namespace KWin
{
class InputDevice;
class InputEventFilter;
class RelativeMotionBlocker : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(KWin::InputDevice *allowedDevice READ allowedDevice WRITE setAllowedDevice NOTIFY allowedDeviceChanged FINAL)
public:
    explicit RelativeMotionBlocker(QObject *parent = nullptr);
    ~RelativeMotionBlocker() override;

    InputDevice *allowedDevice() const;
    void setAllowedDevice(InputDevice *newAllowedDevice);

Q_SIGNALS:
    void allowedDeviceChanged();

private:
    void resetAllowedDevice();
    void updateInputFilter();
    InputEventFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};

} // namespace KWin
