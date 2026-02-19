#!/bin/bash
# detect.sh — Platform, GPU, and runtime user detection

# ── Platform detection ───────────────────────────────────────────────────────
detect_platform() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_LABEL="x86_64" ;;
        aarch64) ARCH_LABEL="ARM (aarch64)" ;;
        *)       ARCH_LABEL="$ARCH (unknown)" ;;
    esac

    # Distro from os-release
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-$NAME}"
        DISTRO_ID="${ID}"
    else
        DISTRO_NAME="Unknown"
        DISTRO_ID="unknown"
    fi

    # Check for pacman
    if ! command -v pacman &>/dev/null; then
        log_error "pacman not found — this installer requires an Arch-based distro"
        exit 1
    fi
}

# ── GPU detection ────────────────────────────────────────────────────────────
detect_gpu() {
    GPU_VENDOR=""
    GPU_DRIVER=""
    VULKAN_ICD_PKG=""
    GPU_EXTRA_ENV=""

    # Priority chain: check loaded kernel modules first
    if lsmod 2>/dev/null | grep -q "^nvidia "; then
        GPU_VENDOR="NVIDIA"
        GPU_DRIVER="nvidia"
        VULKAN_ICD_PKG="nvidia-utils"
        GPU_EXTRA_ENV='__GLX_VENDOR_LIBRARY_NAME=nvidia GBM_BACKEND=nvidia-drm WLR_NO_HARDWARE_CURSORS=1'
    elif lsmod 2>/dev/null | grep -q "^amdgpu "; then
        GPU_VENDOR="AMD"
        GPU_DRIVER="amdgpu"
        VULKAN_ICD_PKG="vulkan-radeon"
    elif lsmod 2>/dev/null | grep -q "^xe "; then
        GPU_VENDOR="Intel"
        GPU_DRIVER="xe"
        VULKAN_ICD_PKG="vulkan-intel"
    elif lsmod 2>/dev/null | grep -q "^i915 "; then
        GPU_VENDOR="Intel"
        GPU_DRIVER="i915"
        VULKAN_ICD_PKG="vulkan-intel"
    elif lsmod 2>/dev/null | grep -q "^panthor "; then
        GPU_VENDOR="ARM (Panthor)"
        GPU_DRIVER="panthor"
        VULKAN_ICD_PKG=""  # Mesa PanVK built-in
        GPU_EXTRA_ENV='DRI_PRIME=1'
    fi

    # Fallback: lspci
    if [ -z "$GPU_VENDOR" ] && command -v lspci &>/dev/null; then
        local vga
        vga=$(lspci 2>/dev/null | grep -i 'vga\|3d\|display')
        if echo "$vga" | grep -qi "nvidia"; then
            GPU_VENDOR="NVIDIA"
            GPU_DRIVER="nvidia (from lspci)"
            VULKAN_ICD_PKG="nvidia-utils"
            GPU_EXTRA_ENV='__GLX_VENDOR_LIBRARY_NAME=nvidia GBM_BACKEND=nvidia-drm WLR_NO_HARDWARE_CURSORS=1'
        elif echo "$vga" | grep -qi "amd\|radeon"; then
            GPU_VENDOR="AMD"
            GPU_DRIVER="amdgpu (from lspci)"
            VULKAN_ICD_PKG="vulkan-radeon"
        elif echo "$vga" | grep -qi "intel"; then
            GPU_VENDOR="Intel"
            GPU_DRIVER="i915/xe (from lspci)"
            VULKAN_ICD_PKG="vulkan-intel"
        fi
    fi

    if [ -z "$GPU_VENDOR" ]; then
        log_warn "Could not detect GPU — Vulkan ICD package must be installed manually"
        GPU_VENDOR="Unknown"
        GPU_DRIVER="none detected"
    fi
}

# ── Runtime user detection ───────────────────────────────────────────────────
detect_runtime_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        INSTALL_USER="$SUDO_USER"
    else
        INSTALL_USER="$(whoami)"
    fi
    INSTALL_HOME=$(eval echo "~$INSTALL_USER")
    INSTALL_UID=$(id -u "$INSTALL_USER")
}

# ── Detection summary ────────────────────────────────────────────────────────
log_summary() {
    echo ""
    echo -e "${BOLD}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│         Platform Detection               │${RESET}"
    echo -e "${BOLD}├─────────────────────────────────────────┤${RESET}"
    echo -e "${BOLD}│${RESET} Architecture : ${CYAN}$ARCH_LABEL${RESET}"
    echo -e "${BOLD}│${RESET} Distro       : ${CYAN}$DISTRO_NAME${RESET}"
    echo -e "${BOLD}│${RESET} GPU Vendor   : ${CYAN}$GPU_VENDOR${RESET}"
    echo -e "${BOLD}│${RESET} GPU Driver   : ${CYAN}$GPU_DRIVER${RESET}"
    echo -e "${BOLD}│${RESET} Vulkan ICD   : ${CYAN}${VULKAN_ICD_PKG:-"(none / built-in)"}${RESET}"
    echo -e "${BOLD}│${RESET} GPU Env Vars : ${CYAN}${GPU_EXTRA_ENV:-"(none)"}${RESET}"
    echo -e "${BOLD}│${RESET} User         : ${CYAN}$INSTALL_USER (UID $INSTALL_UID)${RESET}"
    echo -e "${BOLD}│${RESET} Home         : ${CYAN}$INSTALL_HOME${RESET}"
    echo -e "${BOLD}└─────────────────────────────────────────┘${RESET}"
    echo ""

    if [ "$DRY_RUN" != "true" ]; then
        confirm "Does this look correct?" || {
            log_error "Aborted by user"
            exit 1
        }
    fi
}
