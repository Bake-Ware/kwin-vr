# Shared plumbing for flat-substrate scripted tests (M2 replay harness).
# Source this, then:
#   vrtest_reexec "$@"        # FIRST LINE — private bus + file-backed output
#   boot_flat_kwin <bin-dir>  # sets KPID, LOG; registers cleanup trap
#   activate_vr               # vrActive=true, polls until confirmed
#   vreval '<expr>'           # evaluate QML/JS in the scene, echo result
#   assert_eq <actual> <expected> <msg>
#   fail <msg>                # prints log tail, exits 1
#
# shellcheck shell=bash

# Re-exec under a private dbus session with ALL output going to a file:
# dbus-activated daemons (xdg-desktop-portal etc.) inherit our stdout and
# outlive us — if that's ctest's pipe, ctest waits for EOF until timeout.
vrtest_reexec() {
    if [ -z "${VRTEST_INNER:-}" ]; then
        local out rc
        out=$(mktemp)
        VRTEST_INNER=1 dbus-run-session -- "$0" "$@" > "$out" 2>&1 < /dev/null
        rc=$?
        cat "$out"
        rm -f "$out"
        exit $rc
    fi
}

fail() {
    echo "FAIL: $1"
    if [ -n "${LOG:-}" ] && [ -f "$LOG" ]; then
        echo "--- kwin.log tail:"
        tail -40 "$LOG"
    fi
    exit 1
}

assert_eq() {
    if [ "$1" != "$2" ]; then
        fail "$3 — expected '$2', got '$1'"
    fi
    echo "ok: $3 = '$2'"
}

_vrtest_cleanup() {
    [ -n "${KPID:-}" ] || return 0
    kill -TERM -"$KPID" 2>/dev/null
    sleep 1
    kill -KILL -"$KPID" 2>/dev/null
}

boot_flat_kwin() {
    local bin_dir="${1:?boot_flat_kwin <build-bin-dir>}"
    local kwin="$bin_dir/kwin_wayland"
    [ -x "$kwin" ] || { echo "FAIL: $kwin not executable"; exit 1; }

    export HOME=$(mktemp -d) XDG_RUNTIME_DIR=$(mktemp -d)
    chmod 700 "$XDG_RUNTIME_DIR"
    mkdir -p "$HOME/.config"
    # Tests may pre-set VRTEST_EXTRA_CONFIG with extra [General] kwinvr keys
    # (newline-separated) to pin config-dependent behavior deterministically.
    printf '[General]\ndisplayMode=Flat\n%s' "${VRTEST_EXTRA_CONFIG:-}" > "$HOME/.config/kwinvr"

    export QT_PLUGIN_PATH="$bin_dir"
    export QT_LOGGING_RULES="kwinvr.debug=true"
    export QT_FORCE_STDERR_LOGGING=1
    export KWINVR_TEST_HOOKS=1
    # kwin_wayland must use its own QPA, not the offscreen one CI exports
    unset QT_QPA_PLATFORM

    LOG="$HOME/kwin.log"
    setsid "$kwin" --virtual --no-lockscreen --no-global-shortcuts > "$LOG" 2>&1 &
    KPID=$!
    trap _vrtest_cleanup EXIT

    local on_bus=0 _i
    for _i in $(seq 1 30); do
        if dbus-send --session --dest=org.freedesktop.DBus --print-reply / \
            org.freedesktop.DBus.ListNames 2>/dev/null | grep -q org.kde.kwinvr; then
            on_bus=1; break
        fi
        sleep 1
    done
    [ "$on_bus" = 1 ] || fail "org.kde.kwinvr never appeared on the session bus"
}

activate_vr() {
    dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
        org.freedesktop.DBus.Properties.Set \
        string:org.kde.kwinvr string:vrActive variant:boolean:true \
        > /dev/null 2>&1 || fail "vrActive Set call failed"

    local active=0 _i
    for _i in $(seq 1 30); do
        if dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
            org.freedesktop.DBus.Properties.Get \
            string:org.kde.kwinvr string:vrActive 2>/dev/null \
            | grep -q 'boolean true'; then
            active=1; break
        fi
        sleep 1
    done
    [ "$active" = 1 ] || fail "vrActive never flipped to true"
}

# Evaluate a QML/JS expression in the scene root's context; echoes the result.
# Keep expressions single-line and their results single-line.
vreval() {
    dbus-send --session --dest=org.kde.kwinvr --print-reply /KwinVr \
        org.kde.kwinvr.evalInWorkspace "string:$1" 2>/dev/null \
        | sed -n 's/^ *string "\(.*\)"$/\1/p'
}

# Poll until vreval(expr) == expected or N seconds pass; echoes last value.
vreval_wait() {
    local expr="$1" expected="$2" timeout="${3:-15}" val="" _i
    for _i in $(seq 1 "$timeout"); do
        val=$(vreval "$expr")
        [ "$val" = "$expected" ] && { echo "$val"; return 0; }
        sleep 1
    done
    echo "$val"
    return 1
}
