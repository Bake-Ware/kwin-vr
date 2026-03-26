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

class KwinVrInputDevice;

class KwinInputRemap : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(KWin::KwinVrInputDevice *inputDevice READ inputDevice WRITE setInputDevice NOTIFY inputDeviceChanged FINAL)

public:
    explicit KwinInputRemap(QObject *parent = nullptr);
    ~KwinInputRemap() override;

    KwinVrInputDevice *inputDevice() const;
    void setInputDevice(KwinVrInputDevice *device);

Q_SIGNALS:
    void inputDeviceChanged();

private:
    void rebuildBindings();
    void updateInputFilter();

    InputEventFilter *m_filter = nullptr;
    bool m_filterInstalled = false;
};

} // namespace KWin
