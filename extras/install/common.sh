#!/bin/bash
# common.sh — Shared logging, command execution, and CLI parsing for KWin VR installer

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────
log_info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }

log_phase() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Phase $1: $2${RESET}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${RESET}"
    echo ""
}

# ── Command execution (dry-run aware) ────────────────────────────────────────
run_cmd() {
    if [ "$VERBOSE" = "true" ]; then
        log_info "Running: $*"
    fi
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
        return 0
    fi
    "$@"
}

run_sudo() {
    if [ "$VERBOSE" = "true" ]; then
        log_info "Running (sudo): $*"
    fi
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} sudo $*"
        return 0
    fi
    sudo "$@"
}

# ── Interactive confirmation ─────────────────────────────────────────────────
confirm() {
    local msg="${1:-Continue?}"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would prompt: $msg [y/N]"
        return 0
    fi
    echo -n -e "${BOLD}$msg [y/N]${RESET} "
    read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── CLI flag parsing ─────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false
SKIP_BUILD=false
SKIP_DEPS=false
DO_UNINSTALL=false

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)    DRY_RUN=true ;;
            --verbose)    VERBOSE=true ;;
            --skip-build) SKIP_BUILD=true ;;
            --skip-deps)  SKIP_DEPS=true ;;
            --uninstall)  DO_UNINSTALL=true ;;
            --help|-h)
                echo "Usage: install.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run      Show what would be done without making changes"
                echo "  --verbose      Print commands as they run"
                echo "  --skip-deps    Skip pacman dependency installation"
                echo "  --skip-build   Skip cmake/ninja build step"
                echo "  --uninstall    Remove KWin VR extras and services"
                echo "  --help, -h     Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_error "Run with --help for usage"
                exit 1
                ;;
        esac
        shift
    done
}
