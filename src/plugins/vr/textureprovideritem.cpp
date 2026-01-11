/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "textureprovideritem.h"
#include "kwinvr_logging.h"
#include <QRunnable>
#include <qsgtextureprovider.h>

using namespace KWin;

class SimpleTextureProvider : public QSGTextureProvider
{
public:
    ~SimpleTextureProvider()
    {
        if (m_gl_texture) {
            glDeleteTextures(1, &m_gl_texture);
        }
    }

    QSGTexture *texture() const override
    {
        return m_qsg_texture.get();
    }

    void setTexture(QSGTexture *tex, GLuint gl_texture)
    {
        m_qsg_texture.reset(tex);
        if (m_gl_texture)
            glDeleteTextures(1, &m_gl_texture);

        m_gl_texture = gl_texture;
        Q_EMIT textureChanged();
    }

private:
    std::unique_ptr<QSGTexture> m_qsg_texture;
    GLuint m_gl_texture = 0;
};

TextureProviderItem::TextureProviderItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    // IF this is not set then invalidateSceneGraph
    // is not called when the window dies
    setFlag(ItemHasContents);
}

TextureProviderItem::~TextureProviderItem()
{
    doReleaseResources();
}

QSGTextureProvider *TextureProviderItem::textureProvider() const
{
    if (!m_provider) {
        m_provider = new SimpleTextureProvider();
    }
    return m_provider;
}

void TextureProviderItem::destroyTextureProvider()
{
    delete m_provider;
    m_provider = nullptr;
}

void TextureProviderItem::setTexture(QSGTexture *texture, unsigned int glTexture)
{
    auto prov = static_cast<SimpleTextureProvider *>(textureProvider());
    prov->setTexture(texture, glTexture);
}

void TextureProviderItem::clearTexture()
{
    setTexture(nullptr, 0);
}

void TextureProviderItem::invalidateSceneGraph()
{
    qCDebug(KWINVR) << "TextureProviderItem: Invalidating scene graph";
    destroyTextureProvider();
}

void TextureProviderItem::releaseResources()
{
    doReleaseResources();
}

void TextureProviderItem::doReleaseResources()
{
    if (!m_provider)
        return;

    auto win = window();
    if (!win) {
        qCWarning(KWINVR) << "Failed to release texture, no QQuickWindow";
        return;
    }

    qCDebug(KWINVR) << "TextureProviderItem: Scheduling texture releasee";
    auto texprov = static_cast<SimpleTextureProvider *>(m_provider);
    win->scheduleRenderJob(QRunnable::create([texprov] {
        delete texprov;
    }),
                           QQuickWindow::AfterRenderingStage);
    m_provider = nullptr;
}
