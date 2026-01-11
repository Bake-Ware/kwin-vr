/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuickItem>

class QSGTexture;

namespace KWin
{

class TextureProviderItem : public QQuickItem
{
    Q_OBJECT
public:
    explicit TextureProviderItem(QQuickItem *parent = nullptr);
    ~TextureProviderItem() override;

    // All 5 methods below must be called only from render thread
    bool isTextureProvider() const override
    {
        return true;
    }
    QSGTextureProvider *textureProvider() const override;
    void destroyTextureProvider();
    void setTexture(QSGTexture *texture, unsigned int glTexture);
    void clearTexture();

private Q_SLOTS:
    // Called by scenegraph when it is going to destroy window
    void invalidateSceneGraph();

protected:
    void releaseResources() override;
    void doReleaseResources();

private:
    mutable QSGTextureProvider *m_provider = nullptr;
};

} // namespace KWin
