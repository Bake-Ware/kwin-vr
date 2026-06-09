#!/usr/bin/env bash
# Run the required (non-quarantined) integration test subset.
# Quarantine list: ci/integration-quarantine.txt — triage in doc/TEST_BASELINE.md.
set -euo pipefail
BUILD_DIR="${1:-build}"
[ $# -gt 0 ] && shift
cd "$(dirname "$0")/.."

integration_regex=$(grep -rhoP 'integrationTest\(NAME\s+\K\w+' autotests/integration/ \
    | sed 's/^/^kwin-/;s/$/$/' | paste -sd'|')
quarantine_regex=$(grep -v '^#' ci/integration-quarantine.txt | grep -v '^$' \
    | sed 's/^/^/;s/$/$/' | paste -sd'|')

ctest --test-dir "$BUILD_DIR" --output-on-failure --timeout 300 \
    -R "$integration_regex" -E "$quarantine_regex" "$@"
