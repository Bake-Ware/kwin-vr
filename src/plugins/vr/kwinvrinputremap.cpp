/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrinputremap.h"
#include "input_event.h"
#include "kwinvrconfigwrapper.h"
#include "kwinvrinputdevice.h"

#include <QKeySequence>

namespace KWin
{

using ButtonSetter = void (KwinVrInputDevice::*)(bool);

class InputRemapFilter : public InputEventFilter
{
public:
    explicit InputRemapFilter()
        : InputEventFilter(InputFilterOrder::ButtonRebind)
    {
    }

    bool keyboardKey(KeyboardKeyEvent *event) override
    {
        auto it = m_bindings.find(event->key);
        if (it != m_bindings.end()) {
            (m_inputDevice->*it.value())(event->state != KeyboardKeyState::Released);
            return true;
        }
        return false;
    }

    void releaseAll()
    {
        for (auto it = m_bindings.cbegin(); it != m_bindings.cend(); ++it) {
            (m_inputDevice->*it.value())(false);
        }
        m_bindings.clear();
    }

    KwinVrInputDevice *m_inputDevice = nullptr;
    QHash<Qt::Key, ButtonSetter> m_bindings;
};

static Qt::Key keyFromString(const QString &str)
{
    if (str.isEmpty()) {
        return Qt::Key_unknown;
    }

    // The KCM serializes via QKeySequence::toString(), so this is a round-trip
    QKeySequence seq(str, QKeySequence::PortableText);
    if (!seq.isEmpty()) {
        return seq[0].key();
    }

    return Qt::Key_unknown;
}

KwinInputRemap::KwinInputRemap(QObject *parent)
    : QObject{parent}
    , m_filter(new InputRemapFilter)
{
    auto config = KWinVRConfigWrapper::instance();
    connect(config, &KWinVRConfig::leftClickBindingsChanged, this, &KwinInputRemap::rebuildBindings);
    connect(config, &KWinVRConfig::middleClickBindingsChanged, this, &KwinInputRemap::rebuildBindings);
    connect(config, &KWinVRConfig::rightClickBindingsChanged, this, &KwinInputRemap::rebuildBindings);
    rebuildBindings();
}

KwinInputRemap::~KwinInputRemap()
{
    auto filter = static_cast<InputRemapFilter *>(m_filter);
    filter->releaseAll();
    if (m_filterInstalled && input()) {
        input()->uninstallInputEventFilter(m_filter);
    }
    delete m_filter;
}

KwinVrInputDevice *KwinInputRemap::inputDevice() const
{
    return static_cast<InputRemapFilter *>(m_filter)->m_inputDevice;
}

void KwinInputRemap::setInputDevice(KwinVrInputDevice *device)
{
    auto filter = static_cast<InputRemapFilter *>(m_filter);
    if (filter->m_inputDevice == device) {
        return;
    }

    if (filter->m_inputDevice) {
        filter->releaseAll();
        disconnect(filter->m_inputDevice, nullptr, this, nullptr);
    }

    filter->m_inputDevice = device;

    if (device) {
        connect(device, &QObject::destroyed, this, [this, filter] {
            filter->m_bindings.clear();
            filter->m_inputDevice = nullptr;
            QMetaObject::invokeMethod(this, &KwinInputRemap::updateInputFilter, Qt::QueuedConnection);
        });
        rebuildBindings();
    }

    Q_EMIT inputDeviceChanged();
    QMetaObject::invokeMethod(this, &KwinInputRemap::updateInputFilter, Qt::QueuedConnection);
}

void KwinInputRemap::rebuildBindings()
{
    auto filter = static_cast<InputRemapFilter *>(m_filter);
    if (!filter->m_inputDevice) {
        return;
    }
    filter->releaseAll();

    auto config = KWinVRConfigWrapper::instance();

    auto addBindings = [filter](const QStringList &list, ButtonSetter setter) {
        for (const auto &binding : list) {
            if (binding.isEmpty() || binding == QLatin1String("none")) {
                continue;
            }
            const auto key = keyFromString(binding);
            if (key != Qt::Key_unknown) {
                filter->m_bindings[key] = setter;
            }
        }
    };

    addBindings(config->leftClickBindings(), &KwinVrInputDevice::setLeftButton);
    addBindings(config->middleClickBindings(), &KwinVrInputDevice::setMiddleButton);
    addBindings(config->rightClickBindings(), &KwinVrInputDevice::setRightButton);

    QMetaObject::invokeMethod(this, &KwinInputRemap::updateInputFilter, Qt::QueuedConnection);
}

void KwinInputRemap::updateInputFilter()
{
    auto filter = static_cast<InputRemapFilter *>(m_filter);
    if (filter->m_inputDevice && !filter->m_bindings.isEmpty()) {
        if (!m_filterInstalled) {
            input()->installInputEventFilter(m_filter);
            m_filterInstalled = true;
        }
    } else {
        if (m_filterInstalled) {
            input()->uninstallInputEventFilter(m_filter);
            m_filterInstalled = false;
        }
    }
}

} // namespace KWin
