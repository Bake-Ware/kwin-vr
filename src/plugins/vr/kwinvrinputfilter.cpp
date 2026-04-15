/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrinputfilter.h"
#include "input_event.h"

#include <QCoreApplication>

namespace KWin
{

class VrInputFilter : public InputEventFilter
{
public:
    explicit VrInputFilter(InputFilterOrder::Order weight)
        : InputEventFilter(weight)
    {
    }
    bool keyboardKey(KeyboardKeyEvent *event) override;
    bool pointerButton(PointerButtonEvent *event) override;
    bool pointerAxis(PointerAxisEvent *event) override;
    bool pointerMotion(PointerMotionEvent *event) override;
    bool pinchGestureBegin(PointerPinchGestureBeginEvent *event) override;
    bool pinchGestureUpdate(PointerPinchGestureUpdateEvent *event) override;
    bool pinchGestureEnd(PointerPinchGestureEndEvent *event) override;
    bool pinchGestureCancelled(PointerPinchGestureCancelEvent *event) override;

    QObject *m_eventsTarget = nullptr;
    KwinVrInputFilter *m_owner = nullptr;
    Qt::MouseButtons m_pressedButtons;
    std::chrono::microseconds m_lastPress{0};
    std::chrono::microseconds m_pointerInhibitDelay{100000};
};

bool VrInputFilter::keyboardKey(KeyboardKeyEvent *event)
{
    if (!m_eventsTarget) {
        return false;
    }

    QKeyEvent keyEvent(event->state == KeyboardKeyState::Released ? QEvent::KeyRelease : QEvent::KeyPress,
                       event->key,
                       event->modifiers,
                       event->nativeScanCode,
                       event->nativeVirtualKey,
                       0,
                       event->text,
                       event->state == KeyboardKeyState::Repeated);

    keyEvent.setAccepted(false);
    QCoreApplication::sendEvent(m_eventsTarget, &keyEvent);
    return keyEvent.isAccepted();
}

bool VrInputFilter::pointerButton(PointerButtonEvent *event)
{
    if (!m_eventsTarget) {
        return false;
    }

    QMouseEvent mouseEvent(event->state == PointerButtonState::Pressed ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease,
                           event->position,
                           event->position,
                           event->button,
                           event->buttons,
                           event->modifiers);
    auto ts = std::chrono::duration_cast<std::chrono::milliseconds>(event->timestamp).count();
    mouseEvent.setTimestamp(ts);
    m_lastPress = event->state == PointerButtonState::Pressed ? event->timestamp : std::chrono::microseconds{0};

    mouseEvent.setAccepted(false);
    QCoreApplication::sendEvent(m_eventsTarget, &mouseEvent);
    bool accepted = mouseEvent.isAccepted();

    if (event->state == PointerButtonState::Pressed && accepted) {
        m_pressedButtons.setFlag(event->button, true);
    } else if (event->state == PointerButtonState::Released) {
        // Always accept released events if pressed events were accepted earlier
        if (m_pressedButtons.testFlag(event->button)) {
            m_pressedButtons.setFlag(event->button, false);
            accepted = true;
        }
    }

    return accepted;
}

bool VrInputFilter::pointerAxis(PointerAxisEvent *event)
{
    if (!m_eventsTarget) {
        return false;
    }

    QWheelEvent wheelEvent(event->position,
                           event->position,
                           QPoint(),
                           (event->orientation == Qt::Horizontal) ? QPoint(event->delta, 0) : QPoint(0, event->delta),
                           event->buttons,
                           event->modifiers,
                           Qt::NoScrollPhase,
                           event->inverted);
    wheelEvent.setAccepted(false);
    auto ts = std::chrono::duration_cast<std::chrono::milliseconds>(event->timestamp).count();
    wheelEvent.setTimestamp(ts);
    QCoreApplication::sendEvent(m_eventsTarget, &wheelEvent);
    return wheelEvent.isAccepted();
}

bool VrInputFilter::pointerMotion(PointerMotionEvent *event)
{
    if (m_pointerInhibitDelay.count() < 0) {
        return false;
    }

    if (event->timestamp - m_lastPress < m_pointerInhibitDelay) {
        return true;
    }

    return false;
}

bool VrInputFilter::pinchGestureBegin(PointerPinchGestureBeginEvent *event)
{
    if (!m_owner) {
        return false;
    }
    Q_EMIT m_owner->pinchStarted(event->fingerCount);
    return true;
}

bool VrInputFilter::pinchGestureUpdate(PointerPinchGestureUpdateEvent *event)
{
    if (!m_owner) {
        return false;
    }
    Q_EMIT m_owner->pinchUpdated(event->scale, event->angleDelta);
    return true;
}

bool VrInputFilter::pinchGestureEnd(PointerPinchGestureEndEvent * /*event*/)
{
    if (!m_owner) {
        return false;
    }
    Q_EMIT m_owner->pinchEnded();
    return true;
}

bool VrInputFilter::pinchGestureCancelled(PointerPinchGestureCancelEvent * /*event*/)
{
    if (!m_owner) {
        return false;
    }
    Q_EMIT m_owner->pinchCancelled();
    return true;
}

KwinVrInputFilter::KwinVrInputFilter(QObject *parent)
    : QObject(parent)
{
    m_filter = new VrInputFilter(InputFilterOrder::Effects);
    static_cast<VrInputFilter *>(m_filter)->m_owner = this;
}

KwinVrInputFilter::~KwinVrInputFilter()
{
    if (m_filterInstalled && input()) {
        input()->uninstallInputEventFilter(m_filter);
    }
    delete m_filter;
}

QObject *KwinVrInputFilter::eventsTarget() const
{
    auto filter = static_cast<VrInputFilter *>(m_filter);
    return filter->m_eventsTarget;
}

void KwinVrInputFilter::resetEventsTarget()
{
    setEventsTarget(nullptr);
}

void KwinVrInputFilter::setEventsTarget(QObject *newEventsTarget)
{
    auto filter = static_cast<VrInputFilter *>(m_filter);
    if (filter->m_eventsTarget == newEventsTarget) {
        return;
    }

    if (filter->m_eventsTarget) {
        disconnect(filter->m_eventsTarget, &QObject::destroyed, this, &KwinVrInputFilter::resetEventsTarget);
    }
    if (newEventsTarget) {
        connect(newEventsTarget, &QObject::destroyed, this, &KwinVrInputFilter::resetEventsTarget);
    }
    filter->m_eventsTarget = newEventsTarget;
    Q_EMIT eventsTargetChanged();

    QMetaObject::invokeMethod(this, &KwinVrInputFilter::updateInputFilter, Qt::QueuedConnection);
}

void KwinVrInputFilter::updateInputFilter()
{
    auto filter = static_cast<VrInputFilter *>(m_filter);
    if (filter->m_eventsTarget) {
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

int KwinVrInputFilter::pointerInhibitDelay() const
{
    auto filter = static_cast<VrInputFilter *>(m_filter);
    return std::chrono::duration_cast<std::chrono::milliseconds>(filter->m_pointerInhibitDelay).count();
}

void KwinVrInputFilter::setPointerInhibitDelay(int newPointerInhibitDelay)
{
    auto filter = static_cast<VrInputFilter *>(m_filter);
    const auto newDelay = std::chrono::microseconds(static_cast<qint64>(newPointerInhibitDelay) * 1000);
    if (filter->m_pointerInhibitDelay == newDelay) {
        return;
    }
    filter->m_pointerInhibitDelay = newDelay;

    Q_EMIT pointerInhibitDelayChanged();
}

} // namespace KWin
