/*
    SPDX-FileCopyrightText: 2011 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuickItem>
#include <QUuid>

#include <epoxy/gl.h>
#include <qtimer.h>

namespace KWin
{
class Window;
class GLFramebuffer;
class GLTexture;
class ThumbnailTextureProvider;
class WindowThumbnailSource;

class WindowThumbnailSource : public QObject
{
    Q_OBJECT

public:
    WindowThumbnailSource(QQuickWindow *view, Window *handle);
    ~WindowThumbnailSource() override;

    static std::shared_ptr<WindowThumbnailSource> getOrCreate(QQuickWindow *window, Window *handle);

    struct Frame
    {
        std::shared_ptr<GLTexture> texture;
        GLsync fence;
    };

    Frame acquire();

Q_SIGNALS:
    void changed();

private:
    void update();

    QPointer<QQuickWindow> m_view;
    QPointer<Window> m_handle;

    std::shared_ptr<GLTexture> m_offscreenTexture;
    std::unique_ptr<GLFramebuffer> m_offscreenTarget;
    GLsync m_acquireFence = 0;
    bool m_dirty = true;
    QTimer m_timer;
};

class WindowThumbnailItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QUuid wId READ wId WRITE setWId NOTIFY wIdChanged)
    Q_PROPERTY(KWin::Window *client READ client WRITE setClient NOTIFY clientChanged)

    /**
     * The logical size of the texture for this window, including shadows.
     * This is in device-independent coordinates, not physical pixels.
     */
    Q_PROPERTY(QSizeF textureSizeLogical READ textureSizeLogical NOTIFY textureSizeLogicalChanged FINAL)

    /**
     * The rectangular area within the texture that contains the actual window content, excluding shadows.
     * This is in device-independent coordinates relative to the texture's top-left corner.
     */
    Q_PROPERTY(QRectF textureFrameRect READ textureFrameRect NOTIFY textureFrameRectChanged FINAL)

public:
    explicit WindowThumbnailItem(QQuickItem *parent = nullptr);
    ~WindowThumbnailItem() override;

    QUuid wId() const;
    void setWId(const QUuid &wId);

    Window *client() const;
    void setClient(Window *client);

    QSizeF textureSizeLogical() const;
    QRectF textureFrameRect() const;

    QSGTextureProvider *textureProvider() const override;
    bool isTextureProvider() const override;
    QSGNode *updatePaintNode(QSGNode *oldNode, QQuickItem::UpdatePaintNodeData *) override;

protected:
    void releaseResources() override;
    void itemChange(QQuickItem::ItemChange change, const QQuickItem::ItemChangeData &value) override;

Q_SIGNALS:
    void wIdChanged();
    void clientChanged();
    void textureSizeLogicalChanged();
    void textureFrameRectChanged();

private Q_SLOTS:
   /**
    * @brief Releases graphics resources of this object.
    *
    * This slot is called on the scene graph rendering thread to free graphics
    * resources associated with this object, typically when QQuickWindow is closed
    * or hidden. The OpenGL context is bound when this slot is called.
    *
    * @note Do not remove this slot. It is called directly by the scene graph
    * system via Qt's meta-object mechanism, not through signal-slot connections.
    */
    void invalidateSceneGraph();

private:
    void setTextureSizeLogical(const QSizeF &newTextureSizeLogical);
    void setTextureFrameRect(const QRectF &newTextureFrameRect);

    QRectF paintedRect() const;
    void updateSizes();
    void updateSource();
    void resetSource();

    QUuid m_wId;
    QPointer<Window> m_client;
    QSizeF m_textureSizeLogical = QSizeF(1, 1);
    QRectF m_textureFrameRect = QRectF(0, 0, 1, 1);

    mutable ThumbnailTextureProvider *m_provider = nullptr;
    std::shared_ptr<WindowThumbnailSource> m_source;
};

} // namespace KWin
