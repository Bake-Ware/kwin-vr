#!/bin/bash
# configure.sh — Enable services, reload udev, GPU-specific setup

configure_system() {
    log_phase 6 "Configure System"

    # ── Reload udev ──────────────────────────────────────────────────────
    log_info "Reloading udev rules..."
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
    log_success "Udev rules reloaded"

    # ── Enable system service ────────────────────────────────────────────
    log_info "Enabling vr-headset-init.service..."
    run_sudo systemctl daemon-reload
    run_sudo systemctl enable vr-headset-init.service
    log_success "vr-headset-init.service enabled"

    # ── Enable user services ─────────────────────────────────────────────
    # monado.service is the core runtime — always enable
    # Watch services (xreal-mode-watch, wivrn-watch) are managed dynamically by vr-env.sh
    log_info "Enabling monado.service (user)..."
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} sudo -u $INSTALL_USER systemctl --user enable monado.service"
    else
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user enable monado.service 2>/dev/null || true
    fi
    log_success "monado.service enabled (watch services managed by vr-env.sh)"

    # ── GPU-specific configuration ───────────────────────────────────────
    case "$GPU_VENDOR" in
        NVIDIA)
            log_info "Configuring NVIDIA GPU..."

            # modprobe settings
            local modprobe_conf="/etc/modprobe.d/nvidia-kwin-vr.conf"
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would create $modprobe_conf (modeset=1, fbdev=1)"
            else
                echo "options nvidia_drm modeset=1 fbdev=1" | run_sudo tee "$modprobe_conf" > /dev/null
            fi
            log_success "NVIDIA modprobe config created"

            # Check driver version
            if command -v nvidia-smi &>/dev/null && [ "$DRY_RUN" != "true" ]; then
                local nv_ver
                nv_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
                if [ -n "$nv_ver" ]; then
                    log_info "NVIDIA driver version: $nv_ver"
                fi
            fi
            ;;
        "ARM (Panthor)")
            log_info "ARM Panthor GPU detected"
            log_warn "Note: Panthor typically uses /dev/dri/renderD130 (not renderD128)"
            log_warn "If Monado/WiVRn can't find the GPU, check render node paths"
            ;;
    esac

    # ── Disable screen locker auto-lock ──────────────────────────────────
    log_info "Disabling screen locker auto-lock (prevents VR crash loops)..."
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} kwriteconfig6 --file kscreenlockerrc Autolock=false Timeout=0"
    else
        sudo -u "$INSTALL_USER" \
            kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false 2>/dev/null || true
        sudo -u "$INSTALL_USER" \
            kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 0 2>/dev/null || true
    fi
    log_success "Screen locker auto-lock disabled"

    echo ""
    log_success "System configuration complete"
    log_info "A reboot is recommended to apply all changes"
}
