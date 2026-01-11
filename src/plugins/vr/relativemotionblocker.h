/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef RELATIVEMOTIONBLOCKER_H
#define RELATIVEMOTIONBLOCKER_H

#include <QObject>
#include <QQmlEngine>

/* This class blocks all pointer motion events from kwin when the input is not constrained,
 * except from allowed device.
 *
 * When VR mode is active the head ray is the only input source, so any pointer movement
 * from other input devices will not be passed further.
 *
 * However, when the pointer is constrained (I.e. a gamee requested pointer lock)
 * all events will be poassed further, so you can play Half Life with your mouse as expected.
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
    ~RelativeMotionBlocker();

    KWin::InputDevice *allowedDevice() const;
    void setAllowedDevice(KWin::InputDevice *newAllowedDevice);

Q_SIGNALS:
    void allowedDeviceChanged();

private:
    void resetAllowedDevice();
    void updateInputFilter();
    InputEventFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};
}

#endif // RELATIVEMOTIONBLOCKER_H
