#!/bin/sh
# Every host test: qml/js/Stk.js in QML's own engine (tst_logic.qml) and
# the app with a fake telephonyd (tst_ui.qml).
#
#   tools/run-tests.sh [path to luneos-components]
#
# tools/mutation-check.sh breaks the code on purpose and checks that these
# notice.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
status=0
out=$(tests/run-qml-tests.sh "$LC" 2>&1) || status=1
echo "$out" | grep -E "^(FAIL|Totals)|^   (Actual|Expected|Loc)" || true
exit $status
