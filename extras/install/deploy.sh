#!/bin/bash
# deploy.sh — Deploy extras (scripts, services, udev rules, profiles)

deploy_extras() {
    log_phase 5 "Deploy Extras"

    local extras="$REPO_ROOT/extras"
    local user_systemd="$INSTALL_HOME/.config/systemd/user"

    # ── VR profiles ──────────────────────────────────────────────────────
    log_info "Installing VR profiles..."
    run_sudo mkdir -p /etc/vr-profiles.d
    for f in "$extras"/vr-profiles.d/*.conf; do
        [ -f "$f" ] || continue
        run_sudo cp "$f" /etc/vr-profiles.d/
    done
    log_success "VR profiles installed"

    # ── Udev rules ───────────────────────────────────────────────────────
    log_info "Installing udev rules..."
    for f in "$extras"/udev/rules.d/*.rules; do
        [ -f "$f" ] || continue
        run_sudo cp "$f" /etc/udev/rules.d/
    done
    log_success "Udev rules installed"

    # ── System services (link monitor) ───────────────────────────────────
    log_info "Installing system services..."
    run_sudo cp "$extras/systemd/system/vr-link-monitor.service" /etc/systemd/system/
    run_sudo cp "$extras/systemd/system/vr-link-monitor.timer"   /etc/systemd/system/
    log_success "vr-link-monitor service and timer installed"

    # ── Link monitor helper script ────────────────────────────────────────
    log_info "Installing vr-link-monitor script..."
    run_sudo mkdir -p /usr/lib/vr-link-monitor
    run_sudo cp "$extras/vr-link-monitor/vr-link-monitor" /usr/lib/vr-link-monitor/
    run_sudo chmod 755 /usr/lib/vr-link-monitor/vr-link-monitor
    log_success "vr-link-monitor script installed"

    # ── User services (monado only) ───────────────────────────────────────
    log_info "Installing user services..."
    run_cmd mkdir -p "$user_systemd"

    for f in "$extras"/systemd/user/*.service; do
        [ -f "$f" ] || continue
        local name
        name=$(basename "$f")
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY-RUN]${RESET} Template UID 1000→$INSTALL_UID in $name → $user_systemd/$name"
        else
            sed "s|/run/user/1000|/run/user/$INSTALL_UID|g" "$f" > "$user_systemd/$name"
        fi
    done
    log_success "User services installed (UID templated to $INSTALL_UID)"

    # ── GL_ALPHA shim (ARM only) ─────────────────────────────────────────
    if [ "$ARCH" = "aarch64" ]; then
        log_info "Compiling GL_ALPHA fix shim (ARM)..."
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY-RUN]${RESET} gcc -shared -fPIC -o /usr/lib/libgl_alpha_fix.so gl_alpha_fix.c -ldl"
        else
            run_sudo gcc -shared -fPIC -o /usr/lib/libgl_alpha_fix.so \
                "$extras/gl_alpha_fix.c" -ldl
            if [ $? -ne 0 ]; then
                log_error "Failed to compile GL_ALPHA shim"
                exit 1
            fi
        fi
        log_success "libgl_alpha_fix.so compiled and installed"
    else
        log_info "Skipping GL_ALPHA shim (not ARM)"
    fi

    # ── Optional: SDDM autologin ────────────────────────────────────────
    echo ""
    log_info "SDDM autologin config available (auto-login user '$INSTALL_USER' to Plasma Wayland)"
    if confirm "Deploy SDDM autologin configuration?"; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would template sddm-autologin.conf with User=$INSTALL_USER"
        else
            sed "s/^User=.*/User=$INSTALL_USER/" "$extras/sddm-autologin.conf" \
                | run_sudo tee /etc/sddm.conf.d/autologin.conf > /dev/null
            run_sudo mkdir -p /etc/sddm.conf.d
        fi
        log_success "SDDM autologin deployed"
    else
        log_info "Skipping SDDM autologin"
    fi

    # ── Fix ownership of user files ──────────────────────────────────────
    if [ "$DRY_RUN" != "true" ]; then
        chown -R "$INSTALL_USER:$INSTALL_USER" "$user_systemd" 2>/dev/null
    fi
}
