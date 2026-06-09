#!/usr/bin/env bash
# Run KWin unit tests (everything except autotests/integration).
#
# KWin names all tests kwin-test* with no unit/integration distinction, so we
# derive the integration set from autotests/integration/CMakeLists.txt and
# exclude it. Integration tests run separately per doc/TEST_BASELINE.md.
set -euo pipefail
BUILD_DIR="${1:-build}"
[ $# -gt 0 ] && shift
cd "$(dirname "$0")/.."

integration_regex=$(grep -rhoP 'integrationTest\(NAME\s+\K\w+' autotests/integration/ \
    | sed 's/^/^kwin-/;s/$/$/' | paste -sd'|')

ctest --test-dir "$BUILD_DIR" --output-on-failure -E "$integration_regex" "$@"
