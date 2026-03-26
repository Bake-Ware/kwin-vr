/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrheadscrollfilter.h"
#include "input_event.h"
#include "kwinvrconfigwrapper.h"
#include "kwinvrinputdevice.h"
#include "vrheadscroll.h"

#include <QKeySequence>
#include <QVector2D>

namespace KWin
{

using HeadScrollSetter = void (VrHeadScroll::*)(bool);

class HeadScrollInputFilter : public InputEventFilter
{
public:
    explicit HeadScrollInputFilter()
        : InputEventFilter(static_cast<InputFilterOrder::Order>(InputFilterOrder::ButtonRebind + 1))
    {
    }

    bool keyboardKey(KeyboardKeyEvent *event) override
    {
        auto it = m_keyBindings.find(event->key);
        if (it != m_keyBindings.end()) {
            (m_headScroll->*it.value())(event->state != KeyboardKeyState::Released);
            return true;
        }
        return false;
    }

    bool pointerButton(PointerButtonEvent *event) override
    {
        auto it = m_buttonBindings.find(event->button);
        if (it != m_buttonBindings.end()) {
            (m_headScroll->*it.value())(event->state == PointerButtonState::Pressed);
            return true;
        }
        return false;
    }

    void releaseAll()
    {
        if (m_headScroll) {
            for (auto it = m_keyBindings.cbegin(); it != m_keyBindings.cend(); ++it) {
                (m_headScroll->*it.value())(false);
            }
            for (auto it = m_buttonBindings.cbegin(); it != m_buttonBindings.cend(); ++it) {
                (m_headScroll->*it.value())(false);
            }
        }
        m_keyBindings.clear();
        m_buttonBindings.clear();
    }

    VrHeadScroll *m_headScroll = nullptr;
    QHash<Qt::Key, HeadScrollSetter> m_keyBindings;
    QHash<Qt::MouseButton, HeadScrollSetter> m_buttonBindings;
};

static Qt::Key keyFromString(const QString &str)
{
    if (str.isEmpty()) {
        return Qt::Key_unknown;
    }

    QKeySequence seq(str, QKeySequence::PortableText);
    if (!seq.isEmpty()) {
        return seq[0].key();
    }

    return Qt::Key_unknown;
}

static Qt::MouseButton buttonFromString(const QString &str)
{
    if (str == QLatin1String("MouseLeft")) {
        return Qt::LeftButton;
    }
    if (str == QLatin1String("MouseMiddle")) {
        return Qt::MiddleButton;
    }
    if (str == QLatin1String("MouseRight")) {
        return Qt::RightButton;
    }
    if (str == QLatin1String("MouseBack")) {
        return Qt::BackButton;
    }
    if (str == QLatin1String("MouseForward")) {
        return Qt::ForwardButton;
    }
    return Qt::NoButton;
}

VrHeadScrollFilter::VrHeadScrollFilter(QObject *parent)
    : QObject{parent}
    , m_filter(new HeadScrollInputFilter)
{
    auto config = KWinVRConfigWrapper::instance();
    connect(config, &KWinVRConfig::headScrollBindingsChanged, this, &VrHeadScrollFilter::rebuildBindings);
}

VrHeadScrollFilter::~VrHeadScrollFilter()
{
    auto filter = static_cast<HeadScrollInputFilter *>(m_filter);
    filter->releaseAll();
    if (m_filterInstalled && input()) {
        input()->uninstallInputEventFilter(m_filter);
    }
    delete m_filter;
}

VrHeadScroll *VrHeadScrollFilter::headScroll() const
{
    return static_cast<HeadScrollInputFilter *>(m_filter)->m_headScroll;
}

void VrHeadScrollFilter::setHeadScroll(VrHeadScroll *headScroll)
{
    auto filter = static_cast<HeadScrollInputFilter *>(m_filter);
    if (filter->m_headScroll == headScroll) {
        return;
    }

    if (filter->m_headScroll) {
        filter->releaseAll();
        disconnect(filter->m_headScroll, nullptr, this, nullptr);
    }

    filter->m_headScroll = headScroll;

    if (headScroll) {
        connect(headScroll, &QObject::destroyed, this, [this, filter] {
            filter->m_headScroll = nullptr;
            reconnectWheelForwarding();
            rebuildBindings();
        });
    }

    reconnectWheelForwarding();
    rebuildBindings();
    Q_EMIT headScrollChanged();
}

KwinVrInputDevice *VrHeadScrollFilter::inputDevice() const
{
    return m_inputDevice;
}

void VrHeadScrollFilter::setInputDevice(KwinVrInputDevice *device)
{
    if (m_inputDevice == device) {
        return;
    }

    if (m_inputDevice) {
        disconnect(m_inputDevice, nullptr, this, nullptr);
    }

    m_inputDevice = device;

    if (device) {
        connect(device, &QObject::destroyed, this, [this] {
            m_inputDevice = nullptr;
            reconnectWheelForwarding();
            rebuildBindings();
        });
    }

    reconnectWheelForwarding();
    rebuildBindings();
    Q_EMIT inputDeviceChanged();
}

void VrHeadScrollFilter::rebuildBindings()
{
    auto filter = static_cast<HeadScrollInputFilter *>(m_filter);
    filter->releaseAll();

    if (!filter->m_headScroll || !m_inputDevice) {
        QMetaObject::invokeMethod(this, &VrHeadScrollFilter::updateInputFilter, Qt::QueuedConnection);
        return;
    }

    auto config = KWinVRConfigWrapper::instance();
    const auto bindings = config->headScrollBindings();

    for (const auto &binding : bindings) {
        if (binding.isEmpty() || binding == QLatin1String("none")) {
            continue;
        }

        const auto button = buttonFromString(binding);
        if (button != Qt::NoButton) {
            filter->m_buttonBindings[button] = &VrHeadScroll::setHeadScrollActive;
            continue;
        }

        const auto key = keyFromString(binding);
        if (key != Qt::Key_unknown) {
            filter->m_keyBindings[key] = &VrHeadScroll::setHeadScrollActive;
        }
    }

    QMetaObject::invokeMethod(this, &VrHeadScrollFilter::updateInputFilter, Qt::QueuedConnection);
}

void VrHeadScrollFilter::updateInputFilter()
{
    if (!input()) {
        return;
    }
    auto filter = static_cast<HeadScrollInputFilter *>(m_filter);
    const bool hasBindings = !filter->m_keyBindings.isEmpty() || !filter->m_buttonBindings.isEmpty();
    if (filter->m_headScroll && hasBindings) {
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

void VrHeadScrollFilter::reconnectWheelForwarding()
{
    disconnect(m_wheelConnection);
    m_wheelConnection = {};

    auto filter = static_cast<HeadScrollInputFilter *>(m_filter);
    if (filter->m_headScroll && m_inputDevice) {
        m_wheelConnection = connect(filter->m_headScroll, &VrHeadScroll::wheel, m_inputDevice, [device = m_inputDevice](const QVector2D &delta) {
            device->setAxis(delta.x(), delta.y());
        });
    }
}

} // namespace KWin
