/*
 * GL_ALPHA fix for Qt 6 on GLES 3.0+
 *
 * Qt's QRhiGles2::toGlTextureFormat() uses GL_ALPHA for single-channel
 * textures (glyph cache) when caps.coreProfile is false. GL_ALPHA is
 * invalid on GLES 3.0+.
 *
 * On GLVND systems, Qt resolves GL functions via multiple paths:
 *   - eglGetProcAddress (for some contexts)
 *   - dlsym on a dlopen'd library handle (for others)
 *   - Direct PLT calls (rare on dynamic GL builds)
 *
 * This shim intercepts ALL three paths:
 *   1. Direct symbol exports (LD_PRELOAD)
 *   2. eglGetProcAddress interception
 *   3. dlsym interception via dlvsym bootstrap (no __libc_dlsym needed)
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

/* Only activate for kwin_wayland — other processes (Xwayland, etc.)
 * pass through to real GL functions unmodified. */
static int shim_active = -1; /* -1 = unchecked, 0 = inactive, 1 = active */

static int check_active(void)
{
    if (shim_active >= 0) return shim_active;
    char buf[256];
    ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (len > 0) {
        buf[len] = '\0';
        shim_active = (strstr(buf, "kwin") != NULL) ? 1 : 0;
    } else {
        shim_active = 0;
    }
    if (shim_active)
        fprintf(stderr, "[gl_alpha_fix] Active for: %s\n", buf);
    return shim_active;
}

/* GL constants */
#define GL_RED               0x1903
#define GL_ALPHA             0x1906
#define GL_R8                0x8229
#define GL_TEXTURE_SWIZZLE_R 0x8E42
#define GL_TEXTURE_SWIZZLE_G 0x8E43
#define GL_TEXTURE_SWIZZLE_B 0x8E44
#define GL_TEXTURE_SWIZZLE_A 0x8E45
#define GL_ZERO              0

typedef unsigned int GLenum;
typedef int GLint;
typedef int GLsizei;
typedef void (*pfn_void)(void);

typedef void (*pfn_glTexImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*);
typedef void (*pfn_glTexSubImage2D)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void*);
typedef void (*pfn_glTexStorage2D)(GLenum, GLsizei, GLenum, GLsizei, GLsizei);
typedef void (*pfn_glTexParameteri)(GLenum, GLenum, GLint);
typedef pfn_void (*pfn_eglGetProcAddress)(const char*);

static pfn_glTexImage2D    real_glTexImage2D;
static pfn_glTexSubImage2D real_glTexSubImage2D;
static pfn_glTexStorage2D  real_glTexStorage2D;
static pfn_glTexParameteri real_glTexParameteri;
static pfn_eglGetProcAddress real_eglGetProcAddress;

/* Real dlsym, resolved at init via dlvsym (separate symbol, not affected
 * by our dlsym override). On aarch64 glibc, dlsym is versioned GLIBC_2.17. */
static void *(*real_dlsym)(void *, const char *);

__attribute__((constructor))
static void init(void)
{
    /* dlvsym is a distinct symbol from dlsym, so our override doesn't
     * intercept it. This lets us bootstrap without __libc_dlsym. */
    real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.17");
    if (!real_dlsym) {
        /* Fallback: try other common version strings */
        real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    }
    if (!real_dlsym) {
        fprintf(stderr, "[gl_alpha_fix] WARNING: could not resolve real dlsym via dlvsym\n");
        return;
    }
    real_eglGetProcAddress = (pfn_eglGetProcAddress)real_dlsym(RTLD_NEXT, "eglGetProcAddress");
}

static void resolve_all(void)
{
    if (!real_dlsym) return;
    if (!real_glTexImage2D) {
        real_glTexImage2D = (pfn_glTexImage2D)real_dlsym(RTLD_NEXT, "glTexImage2D");
        if (!real_glTexImage2D && real_eglGetProcAddress)
            real_glTexImage2D = (pfn_glTexImage2D)real_eglGetProcAddress("glTexImage2D");
    }
    if (!real_glTexSubImage2D) {
        real_glTexSubImage2D = (pfn_glTexSubImage2D)real_dlsym(RTLD_NEXT, "glTexSubImage2D");
        if (!real_glTexSubImage2D && real_eglGetProcAddress)
            real_glTexSubImage2D = (pfn_glTexSubImage2D)real_eglGetProcAddress("glTexSubImage2D");
    }
    if (!real_glTexStorage2D) {
        real_glTexStorage2D = (pfn_glTexStorage2D)real_dlsym(RTLD_NEXT, "glTexStorage2D");
        if (!real_glTexStorage2D && real_eglGetProcAddress)
            real_glTexStorage2D = (pfn_glTexStorage2D)real_eglGetProcAddress("glTexStorage2D");
    }
    if (!real_glTexParameteri) {
        real_glTexParameteri = (pfn_glTexParameteri)real_dlsym(RTLD_NEXT, "glTexParameteri");
        if (!real_glTexParameteri && real_eglGetProcAddress)
            real_glTexParameteri = (pfn_glTexParameteri)real_eglGetProcAddress("glTexParameteri");
    }
}

/* Set swizzle: r,g,b → 0, a → red channel (makes GL_R8 look like GL_ALPHA) */
static void set_alpha_swizzle(GLenum target)
{
    if (!real_glTexParameteri) resolve_all();
    if (!real_glTexParameteri) return;
    real_glTexParameteri(target, GL_TEXTURE_SWIZZLE_R, GL_ZERO);
    real_glTexParameteri(target, GL_TEXTURE_SWIZZLE_G, GL_ZERO);
    real_glTexParameteri(target, GL_TEXTURE_SWIZZLE_B, GL_ZERO);
    real_glTexParameteri(target, GL_TEXTURE_SWIZZLE_A, GL_RED);
}

/* === Wrapper functions === */

void glTexImage2D(GLenum target, GLint level, GLint internalformat,
                  GLsizei width, GLsizei height, GLint border,
                  GLenum format, GLenum type, const void *pixels)
{
    if (!real_glTexImage2D) resolve_all();
    if (!real_glTexImage2D) return;
    if (!check_active()) {
        real_glTexImage2D(target, level, internalformat, width, height, border, format, type, pixels);
        return;
    }
    if (internalformat == GL_ALPHA) {
        fprintf(stderr, "[gl_alpha_fix] INTERCEPTED glTexImage2D GL_ALPHA %dx%d -> GL_R8\n", width, height);
        real_glTexImage2D(target, level, GL_R8, width, height, border,
                          GL_RED, type, pixels);
        set_alpha_swizzle(target);
    } else {
        real_glTexImage2D(target, level, internalformat, width, height,
                          border, format, type, pixels);
    }
}

void glTexSubImage2D(GLenum target, GLint level,
                     GLint xoffset, GLint yoffset,
                     GLsizei width, GLsizei height,
                     GLenum format, GLenum type, const void *pixels)
{
    if (!real_glTexSubImage2D) resolve_all();
    if (!real_glTexSubImage2D) return;
    if (check_active() && format == GL_ALPHA)
        format = GL_RED;
    real_glTexSubImage2D(target, level, xoffset, yoffset,
                         width, height, format, type, pixels);
}

void glTexStorage2D(GLenum target, GLsizei levels,
                    GLenum internalformat,
                    GLsizei width, GLsizei height)
{
    if (!real_glTexStorage2D) resolve_all();
    if (!real_glTexStorage2D) return;
    if (!check_active()) {
        real_glTexStorage2D(target, levels, internalformat, width, height);
        return;
    }
    if (internalformat == GL_ALPHA) {
        fprintf(stderr, "[gl_alpha_fix] INTERCEPTED glTexStorage2D GL_ALPHA %dx%d -> GL_R8\n", width, height);
        real_glTexStorage2D(target, levels, GL_R8, width, height);
        set_alpha_swizzle(target);
    } else {
        real_glTexStorage2D(target, levels, internalformat, width, height);
    }
}

/* === eglGetProcAddress override === */

pfn_void eglGetProcAddress(const char *procname)
{
    if (!real_eglGetProcAddress) init();
    if (!real_eglGetProcAddress) return NULL;
    if (!check_active()) return real_eglGetProcAddress(procname);

    if (strcmp(procname, "glTexImage2D") == 0) {
        if (!real_glTexImage2D) resolve_all();
        return (pfn_void)glTexImage2D;
    }
    if (strcmp(procname, "glTexSubImage2D") == 0) {
        if (!real_glTexSubImage2D) resolve_all();
        return (pfn_void)glTexSubImage2D;
    }
    if (strcmp(procname, "glTexStorage2D") == 0) {
        if (!real_glTexStorage2D) resolve_all();
        if (real_glTexStorage2D)
            return (pfn_void)glTexStorage2D;
    }

    return real_eglGetProcAddress(procname);
}

/* === dlsym override — catches dlsym(handle, "glTexImage2D") === */

void *dlsym(void *handle, const char *symbol)
{
    if (!real_dlsym) init();
    if (!real_dlsym) return NULL;
    if (!check_active()) return real_dlsym(handle, symbol);

    if (strcmp(symbol, "glTexImage2D") == 0) {
        if (!real_glTexImage2D) resolve_all();
        return (void *)glTexImage2D;
    }
    if (strcmp(symbol, "glTexSubImage2D") == 0) {
        if (!real_glTexSubImage2D) resolve_all();
        return (void *)glTexSubImage2D;
    }
    if (strcmp(symbol, "glTexStorage2D") == 0) {
        if (!real_glTexStorage2D) resolve_all();
        if (real_glTexStorage2D)
            return (void *)glTexStorage2D;
    }
    if (strcmp(symbol, "eglGetProcAddress") == 0) {
        return (void *)eglGetProcAddress;
    }

    return real_dlsym(handle, symbol);
}
