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

class VrHeadScroll;
class KwinVrInputDevice;

class VrHeadScrollFilter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(KWin::VrHeadScroll *headScroll READ headScroll WRITE setHeadScroll NOTIFY headScrollChanged FINAL)
    Q_PROPERTY(KWin::KwinVrInputDevice *inputDevice READ inputDevice WRITE setInputDevice NOTIFY inputDeviceChanged FINAL)

public:
    explicit VrHeadScrollFilter(QObject *parent = nullptr);
    ~VrHeadScrollFilter() override;

    VrHeadScroll *headScroll() const;
    void setHeadScroll(VrHeadScroll *headScroll);

    KwinVrInputDevice *inputDevice() const;
    void setInputDevice(KwinVrInputDevice *device);

Q_SIGNALS:
    void headScrollChanged();
    void inputDeviceChanged();

private:
    void rebuildBindings();
    void updateInputFilter();
    void reconnectWheelForwarding();

    InputEventFilter *m_filter = nullptr;
    KwinVrInputDevice *m_inputDevice = nullptr;
    bool m_filterInstalled = false;
    QMetaObject::Connection m_wheelConnection;
};

} // namespace KWin
