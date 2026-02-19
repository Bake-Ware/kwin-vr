#!/bin/bash
# deps.sh — Install build dependencies via pacman

install_deps() {
    log_phase 2 "Install Build Dependencies"

    # ── Common packages ──────────────────────────────────────────────────
    local pkgs=(
        # Build tools
        base-devel cmake ninja extra-cmake-modules

        # KDE Frameworks 6
        kconfig kconfigwidgets kcoreaddons kcrash kdbusaddons
        kdeclarative kglobalaccel ki18n kidletime kio
        knewstuff knotifications kpackage krunner kscreenlocker
        ksvg kwayland kwidgetsaddons kwindowsystem kxmlgui
        kdecoration kcolorscheme kcmutils kauth kguiaddons
        kirigami kservice

        # Qt6
        qt6-base qt6-declarative qt6-quick3d qt6-wayland
        qt6-tools qt6-sensors qt6-svg

        # Wayland / display
        wayland wayland-protocols plasma-wayland-protocols
        libinput libdrm mesa

        # OpenXR
        openxr

        # KDE Plasma
        kscreen kglobalacceld

        # Other
        python libdisplay-info hwdata lcms2
        libxkbcommon libepoxy xcb-util-cursor xcb-util-wm
    )

    # ── GPU-conditional packages ─────────────────────────────────────────
    if [ -n "$VULKAN_ICD_PKG" ]; then
        pkgs+=("$VULKAN_ICD_PKG")
    fi

    case "$GPU_DRIVER" in
        panthor)
            pkgs+=(mali-valhall-g610-firmware)
            ;;
    esac

    # ── ARM-conditional packages ─────────────────────────────────────────
    if [ "$ARCH" = "aarch64" ]; then
        pkgs+=(gcc)  # needed to compile GL_ALPHA shim
    fi

    log_info "Installing ${#pkgs[@]} packages via pacman..."
    if [ "$VERBOSE" = "true" ]; then
        log_info "Packages: ${pkgs[*]}"
    fi

    run_sudo pacman -S --needed --noconfirm "${pkgs[@]}"

    if [ $? -eq 0 ]; then
        log_success "Dependencies installed"
    else
        log_error "pacman failed — check output above"
        exit 1
    fi
}
