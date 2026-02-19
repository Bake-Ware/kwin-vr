#!/bin/bash
# uninstall.sh — Remove KWin VR extras and services

do_uninstall() {
    log_phase 1 "Uninstall KWin VR"

    log_warn "This will remove all KWin VR extras, services, and configuration."
    log_warn "KWin VR itself stays installed — use 'pacman -S kwin' to restore stock KWin."
    echo ""
    confirm "Proceed with uninstall?" || {
        log_info "Aborted"
        exit 0
    }

    # ── Detect runtime user ──────────────────────────────────────────────
    detect_runtime_user

    local user_systemd="$INSTALL_HOME/.config/systemd/user"
    local plasma_env="$INSTALL_HOME/.config/plasma-workspace/env"

    # ── Disable services ─────────────────────────────────────────────────
    log_info "Disabling services..."

    run_sudo systemctl disable --now vr-headset-init.service 2>/dev/null || true

    for svc in monado.service xreal-mode-watch.service wivrn-watch.service; do
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY-RUN]${RESET} sudo -u $INSTALL_USER systemctl --user disable --now $svc"
        else
            sudo -u "$INSTALL_USER" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
                XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
                systemctl --user disable --now "$svc" 2>/dev/null || true
        fi
    done
    log_success "Services disabled"

    # ── Remove deployed files ────────────────────────────────────────────
    log_info "Removing deployed files..."

    # System files
    run_sudo rm -rf /usr/lib/vr-headset-init
    run_sudo rm -rf /etc/vr-profiles.d
    run_sudo rm -f /etc/systemd/system/vr-headset-init.service
    run_sudo rm -f /etc/modprobe.d/nvidia-kwin-vr.conf

    # Udev rules
    run_sudo rm -f /etc/udev/rules.d/70-xreal-air.rules
    run_sudo rm -f /etc/udev/rules.d/98-wmr-hololens-config.rules
    run_sudo rm -f /etc/udev/rules.d/99-wmr-headset.rules

    # GL_ALPHA shim
    run_sudo rm -f /usr/lib/libgl_alpha_fix.so

    # User files
    run_cmd rm -f "$user_systemd/monado.service"
    run_cmd rm -f "$user_systemd/xreal-mode-watch.service"
    run_cmd rm -f "$user_systemd/wivrn-watch.service"
    run_cmd rm -f "$plasma_env/vr-env.sh"

    # Runtime detection file
    run_sudo rm -f /run/vr-detected

    log_success "Deployed files removed"

    # ── Reload udev ──────────────────────────────────────────────────────
    log_info "Reloading udev rules..."
    run_sudo udevadm control --reload-rules 2>/dev/null || true
    log_success "Udev rules reloaded"

    # ── Reload systemd ───────────────────────────────────────────────────
    run_sudo systemctl daemon-reload 2>/dev/null || true
    if [ "$DRY_RUN" != "true" ]; then
        sudo -u "$INSTALL_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$INSTALL_UID/bus" \
            XDG_RUNTIME_DIR="/run/user/$INSTALL_UID" \
            systemctl --user daemon-reload 2>/dev/null || true
    fi

    echo ""
    log_success "KWin VR extras uninstalled"
    echo ""
    log_info "To restore stock KWin:"
    log_info "  sudo pacman -S kwin"
    log_info "  sudo reboot"
}
