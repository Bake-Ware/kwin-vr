#!/bin/bash
# KWin VR — Universal Install System
# Supports ARM/x86, multiple GPUs (Panthor, AMD, NVIDIA, Intel),
# and multiple headsets (Samsung Odyssey+, Xreal Air, Quest 3 via WiVRn)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source modules ───────────────────────────────────────────────────────────
source "$REPO_ROOT/extras/install/common.sh"
source "$REPO_ROOT/extras/install/detect.sh"
source "$REPO_ROOT/extras/install/deps.sh"
source "$REPO_ROOT/extras/install/build.sh"
source "$REPO_ROOT/extras/install/deploy.sh"
source "$REPO_ROOT/extras/install/configure.sh"
source "$REPO_ROOT/extras/install/uninstall.sh"

# ── Parse CLI flags ──────────────────────────────────────────────────────────
parse_args "$@"

echo -e "${BOLD}${CYAN}"
echo "  ╦╔═╦ ╦╦╔╗╔  ╦  ╦╦═╗"
echo "  ╠╩╗║║║║║║║  ╚╗╔╝╠╦╝"
echo "  ╩ ╩╚╩╝╩╝╚╝   ╚╝ ╩╚═"
echo -e "${RESET}"
echo -e "  ${BOLD}Universal Installer${RESET}"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY-RUN mode — no changes will be made"
    echo ""
fi

# ── Phase 1: Detect platform ────────────────────────────────────────────────
log_phase 1 "Detect Platform"

detect_platform
detect_gpu
detect_runtime_user
log_summary

# ── Uninstall path ───────────────────────────────────────────────────────────
if [ "$DO_UNINSTALL" = "true" ]; then
    do_uninstall
    exit 0
fi

# ── Phase 2: Install dependencies ───────────────────────────────────────────
if [ "$SKIP_DEPS" = "true" ]; then
    log_info "Skipping dependency installation (--skip-deps)"
else
    install_deps
fi

# ── Phase 3–4: Build and install KWin VR ────────────────────────────────────
if [ "$SKIP_BUILD" = "true" ]; then
    log_info "Skipping build (--skip-build)"
else
    build_kwin_vr
    install_kwin_vr
fi

# ── Phase 5: Deploy extras ──────────────────────────────────────────────────
deploy_extras

# ── Phase 6: Configure system ───────────────────────────────────────────────
configure_system

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  KWin VR installation complete!${RESET}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
echo ""
log_info "Reboot to start using KWin VR"
log_info "To uninstall: ./install.sh --uninstall"
