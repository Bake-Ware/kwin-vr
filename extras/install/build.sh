#!/bin/bash
# build.sh — Build and install KWin VR

build_kwin_vr() {
    log_phase 3 "Build KWin VR"

    local src_dir="$REPO_ROOT"
    local build_dir="$REPO_ROOT/build"

    # ── CMake configure ──────────────────────────────────────────────────
    log_info "Configuring with cmake..."
    run_cmd cmake -B "$build_dir" -S "$src_dir" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DKWIN_BUILD_VR=ON

    if [ $? -ne 0 ]; then
        log_error "cmake configure failed"
        exit 1
    fi

    # ── Verify VR is enabled ─────────────────────────────────────────────
    if [ "$DRY_RUN" != "true" ]; then
        if ! grep -q "KWIN_BUILD_VR:BOOL=ON" "$build_dir/CMakeCache.txt" 2>/dev/null; then
            log_error "KWIN_BUILD_VR is not ON in CMakeCache — check cmake output"
            exit 1
        fi
        log_success "KWIN_BUILD_VR=ON confirmed"

        if grep -q "Qt6Quick3DXr_FOUND:.*=FALSE\|Could NOT find Qt6Quick3DXr" "$build_dir/CMakeCache.txt" 2>/dev/null; then
            log_error "Qt6Quick3DXr not found — VR plugin cannot build"
            log_error "Ensure qt6-quick3d is installed and includes XR support"
            exit 1
        fi
    fi

    # ── Ninja build ──────────────────────────────────────────────────────
    log_info "Building with ninja..."
    run_cmd ninja -C "$build_dir"

    if [ $? -ne 0 ]; then
        log_error "ninja build failed"
        exit 1
    fi

    log_success "KWin VR built successfully"
}

install_kwin_vr() {
    log_phase 4 "Install KWin VR"

    local build_dir="$REPO_ROOT/build"

    log_warn "This will replace your system KWin with KWin VR."
    log_warn "You can restore stock KWin later with: pacman -S kwin"
    echo ""

    confirm "Install KWin VR system-wide?" || {
        log_warn "Skipping KWin VR installation"
        return 0
    }

    run_sudo ninja -C "$build_dir" install

    if [ $? -ne 0 ]; then
        log_error "ninja install failed"
        exit 1
    fi

    # ── Fix RPATH on all installed KWin binaries/libraries ───────────────
    # CMake sets RUNPATH (not RPATH) which only covers direct dependencies.
    # KWin's transitive deps (e.g. libQt6WaylandClient loaded by libkwin.so.6)
    # must also find our custom Qt, so we force RPATH on everything.
    # This is a no-op on systems where kwin was built against system Qt.
    log_info "Fixing RPATH on KWin binaries..."
    if [ "$DRY_RUN" != "true" ] && command -v patchelf &>/dev/null; then
        local kwin_rpath
        kwin_rpath=$(patchelf --print-rpath /usr/bin/kwin_wayland 2>/dev/null)
        if [ -n "$kwin_rpath" ]; then
            # Apply the same RPATH to libkwin.so.6 and the VR plugin so all
            # transitive dependencies are found correctly.
            # Find the versioned libkwin.so dynamically (avoids hardcoding the KDE version).
            local libkwin
            libkwin=$(find /usr/lib -maxdepth 1 -name "libkwin.so.6.*.*" ! -name "libkwin.so.6" 2>/dev/null | head -1)
            if [ -n "$libkwin" ]; then
                run_sudo patchelf --force-rpath --set-rpath "$kwin_rpath" "$libkwin" 2>/dev/null || true
            fi
            run_sudo patchelf --force-rpath --set-rpath "$kwin_rpath" \
                /usr/lib/plugins/kwin/plugins/vr.so 2>/dev/null || true
            run_sudo patchelf --force-rpath --set-rpath "$kwin_rpath" \
                /usr/lib/kwin-vr-custodian 2>/dev/null || true
            # KCMs
            find /usr/lib -name "kcm_kwin*" 2>/dev/null | while read -r f; do
                run_sudo patchelf --force-rpath --set-rpath "$kwin_rpath" "$f" 2>/dev/null || true
            done
            log_success "RPATH fixed"
        fi
    fi

    # Reload the user systemd daemon so it picks up kwin-vr-custodian.service
    # (installed to /usr/lib/systemd/user/ by cmake)
    if [ "$DRY_RUN" != "true" ]; then
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user daemon-reload 2>/dev/null || true
    fi

    log_success "KWin VR installed"
}
