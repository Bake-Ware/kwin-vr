// SPDX-License-Identifier: GPL-2.0-or-later
#include "questframebridge.h"
#include "kwinvrinputdevice.h"
#include "kwinvrhoveredwindowresolver.h"
#include "core/graphicsbufferview.h"
#include "wayland/surface.h"
#include "wayland/subcompositor.h"
#include "window.h"
#include "workspace.h"
#include <KDecoration3/Decoration>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QUuid>
#include <QtEndian>
#include <sys/socket.h>
#include <unistd.h>
#include <cmath>
#include <time.h>

namespace KWin {
namespace {
constexpr int maxWindows = 4;
constexpr int maxWidth = 1280, maxHeight = 720;
void appendU32(QByteArray &bytes, quint32 value) {
    const auto little = qToLittleEndian(value);
    bytes.append(reinterpret_cast<const char *>(&little), 4);
}
bool paintSurface(QPainter &painter, SurfaceInterface *surface, QPointF origin, int depth = 0) {
    if (!surface || depth > 16) return false;
    // Do not silently publish a rotated or inaccessible buffer as a valid frame.
    if (surface->bufferTransform().kind() != OutputTransform::Normal) return false;
    for (auto child : surface->below())
        if (!paintSurface(painter, child->surface(), origin + child->position(), depth + 1)) return false;
    if (auto buffer = surface->buffer()) {
        GraphicsBufferView view(buffer);
        if (view.isNull()) return false;
        painter.drawImage(QRectF(origin, surface->size()), *view.image(), QRectF(surface->bufferSourceBox()));
    }
    for (auto child : surface->above())
        if (!paintSurface(painter, child->surface(), origin + child->position(), depth + 1)) return false;
    return true;
}
void acknowledgeFrame(SurfaceInterface *surface, quint32 time, int depth = 0) {
    if (!surface || depth > 16) return;
    surface->frameRendered(time);
    for (auto child : surface->below()) acknowledgeFrame(child->surface(), time, depth + 1);
    for (auto child : surface->above()) acknowledgeFrame(child->surface(), time, depth + 1);
}
}

QuestFrameBridge::QuestFrameBridge(QObject *parent) : QObject(parent), m_epoch(QUuid::createUuid().toString(QUuid::WithoutBraces)) {
    const auto path = qEnvironmentVariable("QUESTFRAME_BRIDGE_SOCKET");
    if (path.isEmpty()) return;
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    // The supervisor clears this private socket only after stopping its session.
    if (!m_server.listen(path)) {
        qWarning() << "QUESTFRAME_BRIDGE_LISTEN_FAILED" << m_server.errorString();
        return;
    }
    connect(&m_server, &QLocalServer::newConnection, this, &QuestFrameBridge::accept);
    connect(&m_timer, &QTimer::timeout, this, &QuestFrameBridge::publish);
    m_timer.setInterval(100); // diagnostic copy backend, at most 10 complete scenes/s
    qInfo() << "QUESTFRAME_BRIDGE_READY" << path << m_epoch;
}

QuestFrameBridge::~QuestFrameBridge() { disconnectClient(); }

void QuestFrameBridge::accept() {
    while (m_server.hasPendingConnections()) {
        auto socket = m_server.nextPendingConnection();
        struct ucred peer{};
        socklen_t size = sizeof(peer);
        if (m_client || getsockopt(socket->socketDescriptor(), SOL_SOCKET, SO_PEERCRED, &peer, &size)
            || peer.uid != geteuid()) {
            socket->abort(); socket->deleteLater(); continue;
        }
        m_client = socket;
        socket->setReadBufferSize(8192);
        m_device = std::make_unique<KwinVrInputDevice>();
        m_device->setActive(true);
        connect(socket, &QLocalSocket::readyRead, this, &QuestFrameBridge::readCommands);
        connect(socket, &QLocalSocket::disconnected, this, &QuestFrameBridge::disconnectClient);
        m_timer.start();
        publish();
        qInfo() << "QUESTFRAME_BRIDGE_CONNECTED" << peer.pid;
    }
}

void QuestFrameBridge::releaseInput() {
    if (m_device) {
        m_device->setLeftButton(false);
        for (int key : std::as_const(m_keys)) m_device->sendKeyCode(key, false);
    }
    m_keys.clear();
    m_capture.clear();
    m_hover.reset();
}

void QuestFrameBridge::disconnectClient() {
    m_timer.stop();
    releaseInput();
    m_device.reset();
    m_input.clear();
    m_exported.clear();
    if (m_client) {
        auto socket = m_client.data();
        m_client.clear();
        socket->disconnect(this);
        socket->abort();
        socket->deleteLater();
    }
}

int QuestFrameBridge::idFor(Window *window) {
    if (!window) return 0;
    if (!m_ids.contains(window)) {
        m_ids.insert(window, m_nextId++);
        const auto app = window->resourceClass() + QLatin1Char('|') + window->windowRole();
        m_layoutKeys.insert(window, app + QLatin1Char('|') + QString::number(++m_layoutOrdinals[app]));
        connect(window, &QObject::destroyed, this, [this, window] { m_ids.remove(window); m_layoutKeys.remove(window); });
    }
    return m_ids.value(window);
}

void QuestFrameBridge::publish() {
    if (!m_client || m_client->bytesToWrite() != 0 || !workspace()) return;
    QJsonArray windows;
    QByteArray pixels;
    QHash<int, QPointer<Window>> exported;
    for (Window *window : workspace()->stackingOrder()) {
        if (windows.size() == maxWindows) break;
        if (window->isDeleted() || !window->isShown() || !window->surface()
            || !window->isOnCurrentDesktop() || !window->isOnCurrentActivity()) continue;
        const QRectF frame = window->frameGeometry();
        if (frame.width() < 1 || frame.height() < 1 || frame.width() > 8192 || frame.height() > 8192) continue;
        const qreal scale = std::min({1.0, maxWidth / frame.width(), maxHeight / frame.height()});
        const QSize size(qMax(1, qRound(frame.width() * scale)), qMax(1, qRound(frame.height() * scale)));
        QImage image(size, QImage::Format_RGBA8888_Premultiplied);
        if (image.isNull()) continue;
        image.fill(Qt::transparent);
        {
            QPainter painter(&image);
            painter.scale(size.width() / frame.width(), size.height() / frame.height());
            if (auto decoration = window->decoration())
                decoration->paint(&painter, QRect(QPoint(), decoration->size().toSize()));
            if (!paintSurface(painter, window->surface(), window->bufferGeometry().topLeft() - window->frameGeometry().topLeft())) continue;
        }
        const int id = idFor(window);
        exported.insert(id, window);
        windows.append(QJsonObject{{"id", id}, {"parent", idFor(window->transientFor())},
            {"layoutKey", m_layoutKeys.value(window).left(512)},
            {"title", window->caption().left(256)}, {"width", size.width()}, {"height", size.height()},
            {"x", frame.x()}, {"y", frame.y()}, {"logicalWidth", frame.width()}, {"logicalHeight", frame.height()},
            {"bytes", size.width() * size.height() * 4}});
        for (int row = 0; row < image.height(); ++row)
            pixels.append(reinterpret_cast<const char *>(image.constScanLine(row)), image.width() * 4);
    }
    m_exported = exported;
    if (m_device && m_device->leftButton() && (!m_capture || !exported.values().contains(m_capture))) releaseInput();
    const auto json = QJsonDocument(QJsonObject{{"version", 1}, {"epoch", m_epoch},
        {"format", "RGBA8888_PREMULTIPLIED"}, {"windows", windows}}).toJson(QJsonDocument::Compact);
    QByteArray packet("QFW1", 4);
    appendU32(packet, 4 + json.size() + pixels.size());
    appendU32(packet, json.size());
    packet.append(json);
    packet.append(pixels);
    m_client->write(packet);
    // Export is a presentation consumer even when the flat desktop occludes a
    // window. Complete its one-shot callbacks so the client can draw again.
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    const quint32 msec = quint64(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
    for (auto window : std::as_const(m_exported))
        if (window && window->surface()) acknowledgeFrame(window->surface(), msec);
}

void QuestFrameBridge::readCommands() {
    if (!m_client || !m_device) return;
    m_input += m_client->readAll();
    if (m_input.size() > 8192) { disconnectClient(); return; }
    while (m_input.contains('\n')) {
        const int end = m_input.indexOf('\n');
        const auto object = QJsonDocument::fromJson(m_input.left(end)).object();
        m_input.remove(0, end + 1);
        if (object.value("epoch").toString() != m_epoch) continue;
        const auto type = object.value("type").toString();
        if (type == "release") { releaseInput(); continue; }
        if (type == "pointerLeave") {
            m_device->setLeftButton(false);
            m_capture.clear();
            m_hover.reset();
            continue;
        }
        if (type == "key") {
            const int code = object.value("code").toInt(-1);
            if (code < 1 || code > 767) continue;
            const bool down = object.value("down").toBool();
            if (down == m_keys.contains(code)) continue;
            if (down) m_keys.insert(code); else m_keys.remove(code);
            m_device->sendKeyCode(code, down);
            continue;
        }
        Window *window = m_exported.value(object.value("id").toInt()).data();
        if (!window || window->isDeleted()) continue;
        if (type == "close") { window->closeWindow(); continue; }
        if (type != "pointer") continue;
        const double u = object.value("u").toDouble(-1), v = object.value("v").toDouble(-1);
        if (!std::isfinite(u) || !std::isfinite(v)) continue;
        const bool down = object.value("down").toBool();
        if (m_capture) window = m_capture;
        if (!m_hover) m_hover = std::make_unique<KwinVrHoveredWindowResolver>();
        m_hover->setHoveredWindow(window);
        if (down && !m_device->leftButton()) {
            workspace()->activateWindow(window);
            m_capture = window;
        }
        const auto frame = window->frameGeometry();
        m_device->setPointerPosition(frame.topLeft() + QPointF(std::clamp(u, 0.0, 1.0) * (frame.width() - 1),
                                                              std::clamp(v, 0.0, 1.0) * (frame.height() - 1)));
        m_device->setLeftButton(down);
        if (!down) m_capture.clear();
    }
}
}
