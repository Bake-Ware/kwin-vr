// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <memory>

namespace KWin {
class Window;
class KwinVrInputDevice;
class KwinVrHoveredWindowResolver;

// Opt-in bounded CPU-copy bridge. Android owns tracking and XR presentation;
// KWin owns client buffers, decorations, focus and protocol input semantics.
class QuestFrameBridge : public QObject {
public:
    explicit QuestFrameBridge(QObject *parent);
    ~QuestFrameBridge() override;
private:
    void accept();
    void disconnectClient();
    void releaseInput();
    void readCommands();
    void publish();
    int idFor(Window *window);
    QLocalServer m_server;
    QPointer<QLocalSocket> m_client;
    QTimer m_timer;
    QByteArray m_input;
    QString m_epoch;
    int m_nextId = 1;
    QHash<Window *, int> m_ids;
    QHash<Window *, QString> m_layoutKeys;
    QHash<QString, int> m_layoutOrdinals;
    QHash<int, QPointer<Window>> m_exported;
    QPointer<Window> m_capture;
    QSet<int> m_keys;
    std::unique_ptr<KwinVrInputDevice> m_device;
    std::unique_ptr<KwinVrHoveredWindowResolver> m_hover;
};
}
