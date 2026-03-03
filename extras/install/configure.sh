#!/bin/bash
# configure.sh — Enable services, reload udev, GPU-specific setup

configure_system() {
    log_phase 6 "Configure System"

    # ── Reload udev ──────────────────────────────────────────────────────
    log_info "Reloading udev rules..."
    run_sudo udevadm control --reload-rules
    run_sudo udevadm trigger
    log_success "Udev rules reloaded"

    # ── Enable system services ───────────────────────────────────────────
    log_info "Enabling vr-link-monitor.timer..."
    run_sudo systemctl daemon-reload
    run_sudo systemctl enable --now vr-link-monitor.timer
    log_success "vr-link-monitor.timer enabled"

    # ── Enable user services ─────────────────────────────────────────────
    # monado.service is started on-demand by the kwin-vr plugin when SBS mode
    # is detected. Enable it so it can be started/stopped via systemctl --user.
    log_info "Enabling monado.service (user)..."
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} sudo -u $INSTALL_USER systemctl --user enable monado.service"
    else
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user enable monado.service 2>/dev/null || true
    fi
    log_success "monado.service enabled (started on-demand by kwin-vr plugin)"

    # Enable the custodian — it replaces all per-device shell scripts (xreal-mode-watch etc.)
    log_info "Enabling kwin-vr-custodian.service (user)..."
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} sudo -u $INSTALL_USER systemctl --user enable kwin-vr-custodian.service"
    else
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user enable kwin-vr-custodian.service 2>/dev/null || true
        # Disable the old per-device watcher if previously enabled
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user disable xreal-mode-watch.service 2>/dev/null || true
    fi
    log_success "kwin-vr-custodian.service enabled (watches all hardware events, routes to profiles)"

    # ── GPU-specific configuration ───────────────────────────────────────
    case "$GPU_VENDOR" in
        NVIDIA)
            log_info "Configuring NVIDIA GPU..."

            local modprobe_conf="/etc/modprobe.d/nvidia-kwin-vr.conf"
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would create $modprobe_conf (modeset=1, fbdev=1)"
            else
                echo "options nvidia_drm modeset=1 fbdev=1" | run_sudo tee "$modprobe_conf" > /dev/null
            fi
            log_success "NVIDIA modprobe config created"

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
