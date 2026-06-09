#!/usr/bin/env bash
# Ratchet fence for QtQuick3D.Xr coupling (see roadmap M2: the renderer seam).
#
# Goal: everything below the scene root must depend only on QtQuick3D, never
# QtQuick3D.Xr, so a flat-monitor scene can implement the same interface.
# This script fails CI if any file OUTSIDE ci/xr-import-allowlist.txt imports
# QtQuick3D.Xr. Shrinking the allowlist is progress; growing it needs a
# documented reason in the PR.
set -euo pipefail
cd "$(dirname "$0")/.."

current=$(grep -rln 'QtQuick3D\.Xr' src/plugins/vr/ | sort)
offenders=$(comm -23 <(echo "$current") <(sort ci/xr-import-allowlist.txt))

if [ -n "$offenders" ]; then
    echo "ERROR: new QtQuick3D.Xr import(s) outside the allowlist:" >&2
    echo "$offenders" >&2
    echo "Either remove the XR dependency or (with justification) add to ci/xr-import-allowlist.txt" >&2
    exit 1
fi

# Report ratchet progress: files in the allowlist that no longer import Xr
stale=$(comm -13 <(echo "$current") <(sort ci/xr-import-allowlist.txt))
if [ -n "$stale" ]; then
    echo "NOTE: these allowlisted files no longer import QtQuick3D.Xr — shrink the allowlist:"
    echo "$stale"
fi
echo "XR import fence OK ($(echo "$current" | wc -l) allowlisted files)"
