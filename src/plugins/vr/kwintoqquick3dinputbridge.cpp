/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwintoqquick3dinputbridge.h"
#include "input.h"
#include "input_event.h"
#include "kwinvr_logging.h"
/*To get access to delivery agent */
#include <QtQuick/private/qquickitem_p.h>

namespace KWin
{
static inline QEvent::Type getPress(PointerButtonEvent *event)
{
    return (event->state == PointerButtonState::Pressed) ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease;
}

class KWinToQQuick3DFilter : public InputEventFilter
{
public:
    explicit KWinToQQuick3DFilter();
    virtual bool keyboardKey(KeyboardKeyEvent *event) override;
    virtual bool pointerButton(PointerButtonEvent *event) override;
    virtual bool pointerAxis(PointerAxisEvent *event) override;
    virtual bool pointerMotion(PointerMotionEvent *event) override;
    static bool generateMouseEvent(QQuickItem *target, QEvent::Type type, QPointF localCoordinates, Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers);

    /* WE have to keep thsese here because of setPointerPosition
     * Maybe we should pass pointer input events through kwin ? */
    void clear()
    {
        m_modifiers = Qt::NoModifier;
        m_setPointerPosition = QPointF();
        m_buttons = Qt::NoButton;
    }
    Qt::KeyboardModifiers m_modifiers = Qt::NoModifier;
    QPointF m_setPointerPosition;
    Qt::MouseButtons m_buttons = Qt::NoButton;
    QQuickItem *m_target = nullptr;
};

bool KWinToQQuick3DFilter::generateMouseEvent(QQuickItem *target, QEvent::Type type, QPointF localCoordinates, Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    if (!target)
        return false;

    auto da = QQuickItemPrivate::get(target)->deliveryAgent();
    QMouseEvent mouseEvent(type,
                           localCoordinates,
                           localCoordinates,
                           button,
                           buttons,
                           modifiers);

    if (!da) {
        qCWarning(KWINVR) << "No delivery agent found. Can't send mouse event to target:" << target;
        return false;
    }

    auto ret = da->event(&mouseEvent);

    // I Took this from Qt sources,,, and I hove no idea what it does
    if (mouseEvent.isEndEvent()) {
        if (mouseEvent.buttons() == Qt::NoButton) {
            auto &firstPt = mouseEvent.point(0);
            mouseEvent.setExclusiveGrabber(firstPt, nullptr);
            mouseEvent.clearPassiveGrabbers(firstPt);
        }
    }

    return ret;
};

KWinToQQuick3DFilter::KWinToQQuick3DFilter()
    : InputEventFilter(InputFilterOrder::Effects)
{
}

bool KWinToQQuick3DFilter::keyboardKey(KeyboardKeyEvent *event)
{
    if (!m_target)
        return false;

    // Is there a better way to do this?
    QQuickItem *focusedItem = QQuickItemPrivate::get(m_target)->subFocusItem;
    if (!focusedItem) {
        focusedItem = m_target->window()
            ? m_target->window()->activeFocusItem()
            : nullptr;
        if (!focusedItem) {
            qWarning() << "No focusedItem to deliver key events:(";
            return false;
        }

        qCDebug(KWINVR) << "No focusedItem, but got activeFocusItem from window:" << focusedItem;
    } else {
        qCDebug(KWINVR) << "Got subFocusItem item:" << focusedItem;
    }

    m_modifiers = event->modifiers;

    QKeyEvent keyEvent(event->state == KeyboardKeyState::Released ? QEvent::KeyRelease : QEvent::KeyPress,
                       event->key,
                       m_modifiers,
                       event->nativeScanCode,
                       event->nativeVirtualKey,
                       0,
                       event->text,
                       event->state == KeyboardKeyState::Repeated);

    bool ret = QCoreApplication::sendEvent(focusedItem, &keyEvent);
    qCDebug(KWINVR) << "key event delivered ?:" << ret << " accepted? " << keyEvent.isAccepted();
    return ret;
}

bool KWinToQQuick3DFilter::pointerButton(PointerButtonEvent *event)
{
    if (!m_target)
        return false;

    m_buttons = event->buttons;
    m_modifiers = event->modifiers;
    return generateMouseEvent(m_target, getPress(event), m_setPointerPosition, event->button, m_buttons, m_modifiers);
}

bool KWinToQQuick3DFilter::pointerAxis(PointerAxisEvent *event)
{
    if (!m_target)
        return false;

    m_buttons = event->buttons;
    QWheelEvent wheelEvent(m_setPointerPosition,
                           m_setPointerPosition,
                           QPoint(),
                           (event->orientation == Qt::Horizontal) ? QPoint(event->delta, 0) : QPoint(0, event->delta),
                           event->buttons,
                           event->modifiers,
                           Qt::NoScrollPhase,
                           event->inverted);

    auto da = QQuickItemPrivate::get(m_target)->deliveryAgent();
    if (!da) {
        qCWarning(KWINVR) << "No delivery agent";
        return false;
    }

    auto ret = da->event(&wheelEvent);

    return ret;
}

bool KWinToQQuick3DFilter::pointerMotion(PointerMotionEvent *event)
{
    if (!m_target)
        return false;

    m_modifiers = event->modifiers;
    return true;
}

KWinToQQuick3DInputBridge::KWinToQQuick3DInputBridge(QObject *parent)
    : QObject{parent}
    , m_filter(new KWinToQQuick3DFilter)
{
    // input()->installInputEventFilter(m_filter);
}

KWinToQQuick3DInputBridge::~KWinToQQuick3DInputBridge()
{
    if (m_filterInstalled) {
        input()->uninstallInputEventFilter(m_filter);
    }
    delete m_filter;
}

void KWinToQQuick3DInputBridge::updateInputFilter()
{
    if (m_filter->m_target) {
        if (!m_filterInstalled) {
            qCDebug(KWINVR) << "Async installing filter for target" << m_filter->m_target;
            input()->installInputEventFilter(m_filter);
            m_filterInstalled = true;
        }
    } else {
        if (m_filterInstalled) {
            qCDebug(KWINVR) << "Async uninstalling filter";
            input()->uninstallInputEventFilter(m_filter);
            m_filter->clear();
            m_filterInstalled = false;
        }
    }
}

QQuickItem *KWinToQQuick3DInputBridge::target() const
{
    return m_filter->m_target;
}

void KWinToQQuick3DInputBridge::setTarget(QQuickItem *newTarget)
{
    if (m_filter->m_target == newTarget)
        return;

    if (m_filter->m_target) {
        disconnect(m_filter->m_target, nullptr, this, nullptr);
    }

    if (newTarget) {
        connect(newTarget, &QObject::destroyed, this, [this] {
            setTarget(nullptr);
        });
    }

    m_filter->m_target = newTarget;
    Q_EMIT targetChanged();

    QMetaObject::invokeMethod(this, &KWinToQQuick3DInputBridge::updateInputFilter, Qt::QueuedConnection);
}

QPointF KWinToQQuick3DInputBridge::pointerPosition() const
{
    return m_filter->m_setPointerPosition;
}

void KWinToQQuick3DInputBridge::setPointerPosition(QPointF newSetPointerPosition)
{
    if (m_filter->m_setPointerPosition == newSetPointerPosition)
        return;
    m_filter->m_setPointerPosition = newSetPointerPosition;

    m_filter->generateMouseEvent(m_filter->m_target,
                                 QEvent::MouseMove,
                                 m_filter->m_setPointerPosition,
                                 Qt::NoButton,
                                 m_filter->m_buttons,
                                 m_filter->m_modifiers);

    Q_EMIT pointerPositionChanged();
}
}
