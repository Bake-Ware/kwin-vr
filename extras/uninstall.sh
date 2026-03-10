#!/usr/bin/env bash
# kwin-vr uninstall.sh — Cleanly remove everything install.sh deployed
#
# Reads the manifest written by install.sh and reverses every action.
# Safe to run multiple times (idempotent).
#
# Usage:
#   ./uninstall.sh             # Uses ~/kwin-vr-build as BUILD_DIR
#   ./uninstall.sh /path/dir   # Uses custom BUILD_DIR

set -euo pipefail

BUILD_DIR="${1:-$HOME/kwin-vr-build}"
MANIFEST="$BUILD_DIR/.install-manifest"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()    { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
err()     { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*"; }
section() { echo -e "\n${CYAN}══════════ $* ══════════${NC}\n"; }

###############################################################################
# Main
###############################################################################

section "KWin VR Uninstaller"

if [ ! -f "$MANIFEST" ]; then
    err "No install manifest found at $MANIFEST"
    err "Was install.sh run from this BUILD_DIR?"
    exit 1
fi

log "Reading manifest: $MANIFEST"
log "BUILD_DIR: $BUILD_DIR"
echo ""

needs_daemon_reload=false
needs_udev_reload=false
needs_systemd_user_reload=false

# Process manifest in reverse order (undo last actions first)
mapfile -t lines < "$MANIFEST"
for (( i=${#lines[@]}-1; i>=0; i-- )); do
    line="${lines[$i]}"
    [ -z "$line" ] && continue

    type="${line%%:*}"
    path="${line#*:}"

    case "$type" in
        file)
            if [ -f "$path" ]; then
                sudo rm -f "$path"
                log "Removed file: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        dir)
            if [ -d "$path" ]; then
                # Remove all files in the directory, then the directory itself
                sudo rm -rf "$path"
                log "Removed directory: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        symlink)
            if [ -L "$path" ]; then
                rm -f "$path"
                log "Removed symlink: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        script)
            if [ -f "$path" ]; then
                rm -f "$path"
                log "Removed script: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        systemd-system)
            if [ -f "$path" ]; then
                sudo rm -f "$path"
                needs_daemon_reload=true
                log "Removed system unit: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        systemd-user)
            if [ -f "$path" ]; then
                rm -f "$path"
                # Also remove parent dir if it's an override .d directory and now empty
                _parent="$(dirname "$path")"
                if [[ "$_parent" == *.d ]] && [ -d "$_parent" ] && [ -z "$(ls -A "$_parent" 2>/dev/null)" ]; then
                    rmdir "$_parent" 2>/dev/null || true
                fi
                needs_systemd_user_reload=true
                log "Removed user unit: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        systemd-enable)
            if systemctl --user is-enabled "$path" &>/dev/null; then
                systemctl --user stop "$path" 2>/dev/null || true
                systemctl --user disable "$path" 2>/dev/null || true
                log "Disabled: $path"
            else
                warn "Already disabled: $path"
            fi
            ;;

        systemd-mask)
            systemctl --user unmask "$path" 2>/dev/null || true
            log "Unmasked (user): $path"
            ;;

        systemd-mask-global)
            sudo systemctl --global unmask "$path" 2>/dev/null || true
            log "Unmasked (global): $path"
            ;;

        udev)
            if [ -f "$path" ]; then
                sudo rm -f "$path"
                needs_udev_reload=true
                log "Removed udev rule: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        config)
            if [ -f "$path" ]; then
                rm -f "$path"
                log "Removed config: $path"
            else
                warn "Already gone: $path"
            fi
            ;;

        kwinrc)
            # path is like "Plugins/vrEnabled" → group=Plugins, key=vrEnabled
            _group="${path%%/*}"
            _key="${path#*/}"
            kwriteconfig6 --file kwinrc --group "$_group" --key "$_key" --delete 2>/dev/null || true
            log "Removed kwinrc key: $path"
            ;;

        *)
            warn "Unknown manifest type: $type (path: $path)"
            ;;
    esac
done

# Reload daemons as needed
if $needs_daemon_reload; then
    sudo systemctl daemon-reload
    log "Reloaded systemd (system)"
fi

if $needs_systemd_user_reload; then
    systemctl --user daemon-reload
    log "Reloaded systemd (user)"
fi

if $needs_udev_reload; then
    sudo udevadm control --reload-rules
    log "Reloaded udev rules"
fi

# Clean up the KWin VR plugin key from kwinrc
kwriteconfig6 --file kwinrc --group Plugins --key vrEnabled --delete 2>/dev/null || true
log "Removed vrEnabled from kwinrc"

# Remove the manifest itself
rm -f "$MANIFEST"
log "Removed manifest"

section "UNINSTALL COMPLETE"
log "KWin VR state has been removed."
log "Stock KDE Plasma session is restored."
log "Log out and back in (or reboot) for changes to take full effect."
