/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <epoxy/egl.h>
#include <epoxy/gl.h>

#include "kwingraphicshelpers.h"
#include "kwinvr_logging.h"

#include "compositor.h"
#include "core/graphicsbuffer.h"
#include "core/graphicsbufferview.h"
#include "opengl/eglbackend.h"
#include "opengl/egldisplay.h"
#include "utils/drm_format_helper.h"
#include <drm/drm_fourcc.h>

#include <QtGui/QOpenGLContext>

#ifndef DRM_FORMAT_R16F
#define DRM_FORMAT_R16F fourcc_code('R', ' ', ' ', 'H') /* [15:0] R 16 little endian */
#endif
#ifndef DRM_FORMAT_R32F
#define DRM_FORMAT_R32F fourcc_code('R', ' ', ' ', 'F') /* [31:0] R 32 little endian */
#endif

namespace KWin
{

QList<uint32_t> supportedDmabufFormats()
{
    // Formats supported by Qt Rhi
    return {
        // GL_RGBA8 / QRhiTexture::RGBA8
        DRM_FORMAT_XRGB8888,
        DRM_FORMAT_XBGR8888,
        DRM_FORMAT_RGBX8888,
        DRM_FORMAT_BGRX8888,
        DRM_FORMAT_ARGB8888,
        DRM_FORMAT_ABGR8888,
        DRM_FORMAT_RGBA8888,
        DRM_FORMAT_BGRA8888,

        // GL_RGB10_A2 / QRhiTexture::RGB10A2
        DRM_FORMAT_XRGB2101010,
        DRM_FORMAT_XBGR2101010,
        DRM_FORMAT_RGBX1010102,
        DRM_FORMAT_BGRX1010102,
        DRM_FORMAT_ARGB2101010,
        DRM_FORMAT_ABGR2101010,
        DRM_FORMAT_RGBA1010102,
        DRM_FORMAT_BGRA1010102,

        // GL_RGBA16F / QRhiTexture::RGBA16F
        DRM_FORMAT_XRGB16161616F,
        DRM_FORMAT_XBGR16161616F,
        DRM_FORMAT_ARGB16161616F,
        DRM_FORMAT_ABGR16161616F,

        // GL_R8 / QRhiTexture::R8
        DRM_FORMAT_R8,

        // GL_RG8 / QRhiTexture::RG8
        DRM_FORMAT_GR88,

        // GL_R16 / QRhiTexture::R16
        DRM_FORMAT_R16,

        // GL_RG16 / QRhiTexture::RG16
        DRM_FORMAT_GR1616,
        DRM_FORMAT_RG1616,

        // GL_R16F / QRhiTexture::R16F
        DRM_FORMAT_R16F,

        // GL_R32F / QRhiTexture::R32F
        DRM_FORMAT_R32F,

        // GL_R8 / QRhiTexture::R8 (YUV)
        DRM_FORMAT_NV12,

        // GL_R16 / QRhiTexture::R16 (YUV)
        DRM_FORMAT_P010,

        // Not yet supported by Qt:
        // GL_RGBA4 (ARGB/ABGR/RGBA/BGRA4444),
        // GL_RGB5_A1 (ARGB/ABGR/RGBA/BGRA5551),
        // GL_RG16F (GR1616F), GL_RG32F (GR3232F),
        // GL_RGBA32F (ABGR32323232F) - supported, but need testing.
    };
}

QRhiTexture::Format drmFormatToQRhiFormat(uint32_t drmFormat);
EGLImageKHR importDmaBufAsEGLImage(const DmaBufAttributes &dmabuf, EGLDisplay dpy);
EGLImageKHR importDmaBufAsEGLImage(const DmaBufAttributes &dmabuf, EGLDisplay dpy, int plane, int format, const QSize &size);
GLuint createTexFromEGLImage(EGLImageKHR image, bool externalOnly);
EGLDisplay getDisplayFromWin(QQuickWindow *quickWin);
static EglDisplay *eglDisplayFromCompositor();
static bool isExternalOnlyForQt(uint32_t format, uint64_t modifier);

QRhiTexture::Format drmFormatToQRhiFormat(uint32_t drmFormat)
{
    switch (drmFormat) {
    case DRM_FORMAT_XRGB8888:
    case DRM_FORMAT_RGBX8888:
    case DRM_FORMAT_ARGB8888:
    case DRM_FORMAT_RGBA8888:
        return QRhiTexture::Format::RGBA8;
    case DRM_FORMAT_XBGR8888:
    case DRM_FORMAT_BGRX8888:
    case DRM_FORMAT_ABGR8888:
    case DRM_FORMAT_BGRA8888:
        return QRhiTexture::Format::BGRA8;
    case DRM_FORMAT_XRGB2101010:
    case DRM_FORMAT_XBGR2101010:
    case DRM_FORMAT_RGBX1010102:
    case DRM_FORMAT_BGRX1010102:
    case DRM_FORMAT_ARGB2101010:
    case DRM_FORMAT_ABGR2101010:
    case DRM_FORMAT_RGBA1010102:
    case DRM_FORMAT_BGRA1010102:
        return QRhiTexture::Format::RGB10A2;
    case DRM_FORMAT_XRGB16161616F:
    case DRM_FORMAT_XBGR16161616F:
    case DRM_FORMAT_ARGB16161616F:
    case DRM_FORMAT_ABGR16161616F:
        return QRhiTexture::Format::RGBA16F;
    case DRM_FORMAT_R8:
        return QRhiTexture::Format::R8;
    case DRM_FORMAT_GR88:
        return QRhiTexture::Format::RG8;
    case DRM_FORMAT_R16:
        return QRhiTexture::Format::R16;
    case DRM_FORMAT_R16F:
        return QRhiTexture::Format::R16F;
    case DRM_FORMAT_GR1616:
    case DRM_FORMAT_RG1616:
        return QRhiTexture::Format::RG16;
    case DRM_FORMAT_R32F:
        return QRhiTexture::Format::R32F;
    // TODO: DRM_FORMAT_ABGR32323232F  // QRhiTexture::RGBA32F need testing
    default:
        return QRhiTexture::Format::UnknownFormat;
    }
}

EGLImageKHR importDmaBufAsEGLImage(const DmaBufAttributes &dmabuf, EGLDisplay dpy)
{
    QList<EGLint> attribs;
    attribs.reserve(6 + dmabuf.planeCount * 10 + 1);

    attribs << EGL_WIDTH << dmabuf.width
            << EGL_HEIGHT << dmabuf.height
            << EGL_LINUX_DRM_FOURCC_EXT << dmabuf.format;

    attribs << EGL_DMA_BUF_PLANE0_FD_EXT << dmabuf.fd[0].get()
            << EGL_DMA_BUF_PLANE0_OFFSET_EXT << dmabuf.offset[0]
            << EGL_DMA_BUF_PLANE0_PITCH_EXT << dmabuf.pitch[0];
    if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
        attribs << EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT << EGLint(dmabuf.modifier & 0xffffffff)
                << EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT << EGLint(dmabuf.modifier >> 32);
    }

    if (dmabuf.planeCount > 1) {
        attribs << EGL_DMA_BUF_PLANE1_FD_EXT << dmabuf.fd[1].get()
                << EGL_DMA_BUF_PLANE1_OFFSET_EXT << dmabuf.offset[1]
                << EGL_DMA_BUF_PLANE1_PITCH_EXT << dmabuf.pitch[1];
        if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
            attribs << EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT << EGLint(dmabuf.modifier & 0xffffffff)
                    << EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT << EGLint(dmabuf.modifier >> 32);
        }
    }

    if (dmabuf.planeCount > 2) {
        attribs << EGL_DMA_BUF_PLANE2_FD_EXT << dmabuf.fd[2].get()
                << EGL_DMA_BUF_PLANE2_OFFSET_EXT << dmabuf.offset[2]
                << EGL_DMA_BUF_PLANE2_PITCH_EXT << dmabuf.pitch[2];
        if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
            attribs << EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT << EGLint(dmabuf.modifier & 0xffffffff)
                    << EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT << EGLint(dmabuf.modifier >> 32);
        }
    }

    if (dmabuf.planeCount > 3) {
        attribs << EGL_DMA_BUF_PLANE3_FD_EXT << dmabuf.fd[3].get()
                << EGL_DMA_BUF_PLANE3_OFFSET_EXT << dmabuf.offset[3]
                << EGL_DMA_BUF_PLANE3_PITCH_EXT << dmabuf.pitch[3];
        if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
            attribs << EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT << EGLint(dmabuf.modifier & 0xffffffff)
                    << EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT << EGLint(dmabuf.modifier >> 32);
        }
    }

    attribs << EGL_NONE;

    return eglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attribs.data());
}

EGLImageKHR importDmaBufAsEGLImage(const DmaBufAttributes &dmabuf, EGLDisplay dpy, int plane, int format, const QSize &size)
{
    QList<EGLint> attribs;
    attribs.reserve(6 + 1 * 10 + 1);

    attribs << EGL_WIDTH << size.width()
            << EGL_HEIGHT << size.height()
            << EGL_LINUX_DRM_FOURCC_EXT << format;

    attribs << EGL_DMA_BUF_PLANE0_FD_EXT << dmabuf.fd[plane].get()
            << EGL_DMA_BUF_PLANE0_OFFSET_EXT << dmabuf.offset[plane]
            << EGL_DMA_BUF_PLANE0_PITCH_EXT << dmabuf.pitch[plane];
    if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
        attribs << EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT << EGLint(dmabuf.modifier & 0xffffffff)
                << EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT << EGLint(dmabuf.modifier >> 32);
    }
    attribs << EGL_NONE;

    return eglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attribs.data());
}

GLuint createTexFromEGLImage(EGLImageKHR image, bool externalOnly)
{
    if (image == EGL_NO_IMAGE)
        return 0;

    GLuint texture = 0;

    glGenTextures(1, &texture);
    if (!texture) {
        return 0;
    }

    const uint32_t target = externalOnly ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D;
    glBindTexture(target, texture);
    glEGLImageTargetTexture2DOES(target, image);
    glBindTexture(target, 0);

    return texture;
}

EGLDisplay getDisplayFromWin(QQuickWindow *quickWin)
{
    QRhi *rhi = quickWin->rhi();
    if (!rhi) {
        qCWarning(KWINVR) << "No rhi";
        return EGL_NO_DISPLAY;
    }
    const QRhiGles2NativeHandles *openglRhi = static_cast<const QRhiGles2NativeHandles *>(rhi->nativeHandles());
    if (!openglRhi) {
        qCWarning(KWINVR) << "No gles2 native handles";
        return EGL_NO_DISPLAY;
    }
    auto context = openglRhi->context;
    auto nativeContext = context->nativeInterface<QNativeInterface::QEGLContext>();
    if (!nativeContext) {
        qCWarning(KWINVR) << "No QNativeInterface::QEGLContext";
        return EGL_NO_DISPLAY;
    }
    return nativeContext->display();
}

static EglDisplay *eglDisplayFromCompositor()
{
    auto *compositor = Compositor::self();
    if (!compositor) {
        return nullptr;
    }
    auto *backend = compositor->backend();
    auto *eglBackend = qobject_cast<EglBackend *>(backend);
    return eglBackend ? eglBackend->eglDisplayObject() : nullptr;
}

static bool isExternalOnlyForQt(uint32_t format, uint64_t modifier)
{
    if (auto *eglDisplay = eglDisplayFromCompositor()) {
        return eglDisplay->isExternalOnly(format, modifier);
    }
    return false;
}

QRhiTexture *RHITextureFromGL(QRhi *rhi, GLuint texture, QRhiTexture::Format rhiFormat, const QSize &size, QRhiTexture::Flags flags)
{
    auto rhiTex = rhi->newTexture(rhiFormat, size, 1, flags);
    if (!rhiTex) {
        qCWarning(KWINVR) << "Failed to make a new QRhi texture";
        return nullptr;
    }

    if (!rhiTex->createFrom({texture, 0})) {
        qCWarning(KWINVR) << "Failed to create a new QRhi texture from OpemGL texture";
        delete rhiTex;
        return nullptr;
    }
    return rhiTex;
}

QSGTexture *QSGTextureFromGL(const QQuickWindow *quickWin, GLuint texture, QRhiTexture::Format rhiFormat, const QSize &size, bool hasAlphaChannel, QRhiTexture::Flags flags)
{
    auto rhiTex = RHITextureFromGL(quickWin->rhi(), texture, rhiFormat, size, flags);
    if (!rhiTex) {
        return nullptr;
    }

    auto qsgTex = quickWin->createTextureFromRhiTexture(rhiTex, hasAlphaChannel ? QQuickWindow::TextureHasAlphaChannel : QQuickWindow::CreateTextureOptions{});
    if (!qsgTex) {
        qCWarning(KWINVR) << "Failed to create QSGTexture from RHI texture";
        delete rhiTex;
        return nullptr;
    }

    return qsgTex;
}

QtTexturePair importDmaBufPlaneToQtTexturePair(QQuickWindow *quickWin,
                                               const DmaBufAttributes &dmabuf,
                                               int plane,
                                               int drmFormat,
                                               QRhiTexture::Format rhiFormat,
                                               const QSize &size,
                                               bool hasAlphaChannel)
{

    EGLDisplay dpy = getDisplayFromWin(quickWin);
    if (dpy == EGL_NO_DISPLAY) {
        qCWarning(KWINVR) << "Could not get egl display";
        return {};
    }

    EGLImageKHR image = importDmaBufAsEGLImage(dmabuf, dpy, plane, drmFormat, size);
    if (image == EGL_NO_IMAGE) {
        qCWarning(KWINVR) << "Failed to import dmabuf! format:"
                          << dmabuf.format << "modifier:"
                          << dmabuf.modifier << "planecount:"
                          << dmabuf.planeCount << "pitch:"
                          << dmabuf.pitch << "width:"
                          << dmabuf.width << "height:"
                          << dmabuf.height << "";
        return {};
    }

    const bool externalOnly = isExternalOnlyForQt(drmFormat, dmabuf.modifier);
    GLuint texture = createTexFromEGLImage(image, externalOnly);
    eglDestroyImageKHR(dpy, image);

    if (!texture) {
        qCWarning(KWINVR) << "Failed to create OpenGL texture from EGLImage";
        return {};
    }

    const auto flags = externalOnly ? QRhiTexture::ExternalOES : QRhiTexture::Flags{};
    QSGTexture *qsgTexture = QSGTextureFromGL(quickWin, texture, rhiFormat, size, hasAlphaChannel, flags);
    if (!qsgTexture) {
        qCWarning(KWINVR) << "Failed to create QSGTexture from OpenGL texture";
        glDeleteTextures(1, &texture);
        return {};
    }

    return {texture, qsgTexture};
}

QtTexturePair importDmaBufToQtTexturePair(QQuickWindow *quickWin,
                                          const DmaBufAttributes &dmabuf,
                                          QRhiTexture::Format rhiFormat,
                                          const QSize &size,
                                          bool hasAlphaChannel)
{

    EGLDisplay dpy = getDisplayFromWin(quickWin);
    if (dpy == EGL_NO_DISPLAY) {
        qCWarning(KWINVR) << "Could not get egl display";
        return {};
    }

    EGLImageKHR image = importDmaBufAsEGLImage(dmabuf, dpy);
    if (image == EGL_NO_IMAGE) {
        qCWarning(KWINVR) << "Failed to import dmabuf! format:"
                          << dmabuf.format << "modifier:"
                          << dmabuf.modifier << "planecount:"
                          << dmabuf.planeCount << "pitch:"
                          << dmabuf.pitch << "width:"
                          << dmabuf.width << "height:"
                          << dmabuf.height << "";
        return {};
    }

    const bool externalOnly = isExternalOnlyForQt(dmabuf.format, dmabuf.modifier);
    GLuint texture = createTexFromEGLImage(image, externalOnly);
    eglDestroyImageKHR(dpy, image);

    if (!texture) {
        qCWarning(KWINVR) << "Failed to create OpenGL texture from EGLImage";
        return {};
    }

    const auto flags = externalOnly ? QRhiTexture::ExternalOES : QRhiTexture::Flags{};
    QSGTexture *qttexture = QSGTextureFromGL(quickWin, texture, rhiFormat, size, hasAlphaChannel, flags);
    if (!qttexture) {
        qCWarning(KWINVR) << "Failed to create QSGTexture from OpenGL texture";
        glDeleteTextures(1, &texture);
        return {};
    }

    return {texture, qttexture};
}

GraphicsBufferTextures importDmaBufToQSGTextures(QQuickWindow *quickWin, GraphicsBuffer *buf)
{
    if (!quickWin) {
        qCWarning(KWINVR) << "No quick window when trying to import dmabuf";
        return {};
    }

    const DmaBufAttributes *dmaBufAttrs = buf->dmabufAttributes();
    if (!dmaBufAttrs) {
        qCWarning(KWINVR) << "Could not get dmaBufAttrs";
        return {};
    }

    const auto info = FormatInfo::get(dmaBufAttrs->format);
    if (!info) {
        qCWarning(KWINVR) << "Failed to get texture format from dmabuf";
        return {};
    }

    if (const auto yuvConv = info->yuvConversion()) {
        GraphicsBufferTextures qtTextures;

        for (uint plane = 0; plane < yuvConv->plane.count(); ++plane) {
            const auto &currentPlane = yuvConv->plane[plane];
            QSize size = buf->size();
            size.rwidth() /= currentPlane.widthDivisor;
            size.rheight() /= currentPlane.heightDivisor;

            auto rhiFormat = drmFormatToQRhiFormat(currentPlane.format);
            if (rhiFormat == QRhiTexture::UnknownFormat) {
                qCWarning(KWINVR) << "Failed to map yuv plane format to QRhi texture format";
                qtTextures.release();
                return {};
            }

            /* What about size of texture? */
            auto texpair = importDmaBufPlaneToQtTexturePair(quickWin, *dmaBufAttrs, plane, currentPlane.format, rhiFormat, size, false);
            if (!texpair.qtTexture) {
                qCWarning(KWINVR) << "Failed to import dmabuf to qttexture";
                qtTextures.release();
                return {};
            }

            qtTextures.planeTextures[plane] = texpair;
            qtTextures.planeCount++;
        }

        return qtTextures;
    } else {
        const auto rhiFormat = drmFormatToQRhiFormat(dmaBufAttrs->format);
        if (rhiFormat == QRhiTexture::UnknownFormat) {
            qCWarning(KWINVR) << "Failed to map dmabuf format to QRhi texture format";
            return {};
        }
        auto texPair = importDmaBufToQtTexturePair(quickWin, *dmaBufAttrs, rhiFormat, buf->size(), buf->hasAlphaChannel());
        if (!texPair.qtTexture) {
            qCWarning(KWINVR) << "Failed to import dmabuf texture";
            return {};
        }

        return {
            .planeTextures = {texPair},
            .planeCount = 1,
        };
    }
}

/*
 * EGL readback helper: a lightweight GL context on the compositor's EGL
 * display used to import dmabufs via EGL images and read pixels back to CPU.
 * This works for tiled/non-linear dmabufs that GraphicsBufferView::map()
 * cannot handle, at the cost of a GPU→CPU→GPU round-trip.
 */
struct EglReadbackHelper
{
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    bool initialized = false;
    bool failed = false;

    bool init(EGLDisplay dpy)
    {
        if (initialized)
            return display == dpy;
        if (failed)
            return false;
        display = dpy;

        // Try desktop GL first, then GLES 3. Use surfaceless context
        // (EGL_KHR_surfaceless_context) so we don't need pbuffer surfaces,
        // which GBM-backed EGL displays may not support.
        struct
        {
            EGLenum api;
            EGLint renderableType;
            const char *name;
        } tries[] = {
            {EGL_OPENGL_API, EGL_OPENGL_BIT, "GL"},
            {EGL_OPENGL_ES_API, EGL_OPENGL_ES3_BIT, "GLES3"},
        };

        for (auto &t : tries) {
            if (!eglBindAPI(t.api))
                continue;

            // Accept any config for this API; we only render to FBOs
            EGLint configAttribs[] = {
                EGL_RENDERABLE_TYPE,
                t.renderableType,
                EGL_NONE,
            };
            EGLConfig config;
            EGLint numConfigs;
            if (!eglChooseConfig(display, configAttribs, &config, 1, &numConfigs) || numConfigs == 0)
                continue;

            EGLint ctxAttribs[] = {
                EGL_CONTEXT_MAJOR_VERSION,
                3,
                EGL_CONTEXT_MINOR_VERSION,
                0,
                EGL_NONE,
            };
            context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctxAttribs);
            if (context == EGL_NO_CONTEXT)
                continue;

            // Use surfaceless — we only need FBO rendering
            surface = EGL_NO_SURFACE;
            initialized = true;
            qCDebug(KWINVR) << "EGL readback: created" << t.name << "context (surfaceless)";
            return true;
        }

        qCWarning(KWINVR) << "EGL readback: no suitable GL/GLES context";
        failed = true;
        return false;
    }

    bool activate()
    {
        return eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
    }

    void deactivate()
    {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
};

static thread_local EglReadbackHelper s_readbackHelper;

static GraphicsBufferTextures importDmaBufViaEglReadback(QQuickWindow *win, GraphicsBuffer *buf)
{
    auto *eglDpy = eglDisplayFromCompositor();
    if (!eglDpy) {
        qCWarning(KWINVR) << "EGL readback: no compositor EGL display";
        return {};
    }

    EGLDisplay dpy = eglDpy->handle();
    if (!s_readbackHelper.init(dpy)) {
        return {};
    }

    const DmaBufAttributes *dmabuf = buf->dmabufAttributes();
    if (!dmabuf) {
        return {};
    }

    if (eglDpy->isExternalOnly(dmabuf->format, dmabuf->modifier)) {
        qCWarning(KWINVR) << "EGL readback: external-only format, cannot FBO-readback";
        return {};
    }

    // Import dmabuf as EGL image (no GL context required)
    EGLImageKHR image = eglDpy->importDmaBufAsImage(*dmabuf);
    if (image == EGL_NO_IMAGE) {
        qCWarning(KWINVR) << "EGL readback: importDmaBufAsImage failed"
                          << "format:" << dmabuf->format
                          << "modifier:" << dmabuf->modifier;
        return {};
    }

    // Save current EGL state (Vulkan render thread may or may not have one)
    EGLContext prevCtx = eglGetCurrentContext();
    EGLSurface prevDraw = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface prevRead = eglGetCurrentSurface(EGL_READ);
    EGLDisplay prevDpy = eglGetCurrentDisplay();

    if (!s_readbackHelper.activate()) {
        qCWarning(KWINVR) << "EGL readback: failed to make context current";
        eglDpy->destroyImage(image);
        return {};
    }

    // Bind EGL image to GL texture
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);
    glBindTexture(GL_TEXTURE_2D, 0);
    eglDpy->destroyImage(image);

    if (!texture) {
        if (prevCtx != EGL_NO_CONTEXT)
            eglMakeCurrent(prevDpy, prevDraw, prevRead, prevCtx);
        else
            s_readbackHelper.deactivate();
        return {};
    }

    // FBO readback
    const int w = dmabuf->width;
    const int h = dmabuf->height;

    GLuint fbo = 0;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);

    GraphicsBufferTextures result;

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
        const auto imgFmt = buf->hasAlphaChannel() ? QImage::Format_RGBA8888
                                                   : QImage::Format_RGBX8888;
        QImage qimg(w, h, imgFmt);
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, qimg.bits());

        // Cleanup GL resources before calling into Qt
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &texture);

        // Restore EGL state
        if (prevCtx != EGL_NO_CONTEXT)
            eglMakeCurrent(prevDpy, prevDraw, prevRead, prevCtx);
        else
            s_readbackHelper.deactivate();

        auto *qsgTex = win->createTextureFromImage(
            qimg,
            buf->hasAlphaChannel() ? QQuickWindow::TextureHasAlphaChannel
                                   : QQuickWindow::CreateTextureOptions{});
        if (qsgTex) {
            result.planeTextures[0] = {0, qsgTex};
            result.planeCount = 1;
        } else {
            qCWarning(KWINVR) << "EGL readback: createTextureFromImage failed";
        }
    } else {
        qCWarning(KWINVR) << "EGL readback: framebuffer incomplete:" << glCheckFramebufferStatus(GL_FRAMEBUFFER);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &texture);

        if (prevCtx != EGL_NO_CONTEXT)
            eglMakeCurrent(prevDpy, prevDraw, prevRead, prevCtx);
        else
            s_readbackHelper.deactivate();
    }

    return result;
}

GraphicsBufferTextures loadGraphicsBufferToQSGTextures(GraphicsBuffer *buf, QQuickWindow *win)
{
    if (buf->shmAttributes() || buf->singlePixelAttributes()) {
        GraphicsBufferView v(buf);
        if (v.isNull()) {
            qCWarning(KWINVR) << "Failed to create texture from shm buffer";
            return {};
        }

        /* Is it safe ?
         *
         * GraphicsBufferView makes QImages by wrapping it around shm buffer.
         * Does createTextureFromImage() loads the image to the texture before return
         * or it loads it later?
         *
         * So far, I've seen no problems, but need to dig Qt Sources to verify that it is safe...
         */
        auto tex = win->createTextureFromImage(*v.image());
        if (!tex) {
            qCWarning(KWINVR) << "Failed to create QSGTexture from QImage";
            return {};
        }

        return {
            .planeTextures = {{0, tex}},
            .planeCount = 1};
    } else {
        // When the RHI backend is Vulkan (e.g. for OpenXR), the direct
        // EGL→GL→QRhiTexture import path cannot work because QRhiGles2
        // native handles are unavailable. Instead, import the dmabuf via
        // the compositor's EGL display, readback through a helper GL
        // context, and upload to the Vulkan RHI via createTextureFromImage.
        QRhi *rhi = win ? win->rhi() : nullptr;
        if (rhi && rhi->backend() != QRhi::OpenGLES2) {
            return importDmaBufViaEglReadback(win, buf);
        }
        return importDmaBufToQSGTextures(win, buf);
    }
};

void GraphicsBufferTextures::release()
{
    for (auto texPair : std::span<QtTexturePair>(planeTextures, planeCount)) {
        delete texPair.qtTexture;
        if (texPair.glTexture) {
            glDeleteTextures(1, &texPair.glTexture);
        }
    }
    planeCount = 0;
}

};
