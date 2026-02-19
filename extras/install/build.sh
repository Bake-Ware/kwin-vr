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

    log_success "KWin VR installed"
}
