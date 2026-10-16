#!/bin/bash
# Breaks the app on purpose, one way at a time, and checks that the tests
# notice: each mutation below must make tools/run-tests.sh fail. The file
# is put back after each, and on exit.
#
#   tools/mutation-check.sh [path to luneos-components]
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
SAVE=build/mutation
mkdir -p "$SAVE"
current=""
restore() { [ -n "$current" ] && cp "$SAVE/original" "$current"; current=""; }
trap restore EXIT

# what ¦ file ¦ text ¦ replacement (\n for a new line)
mutations=(
"back prefers ending the session ¦ qml/js/Stk.js ¦     if (allowed(request, \"goBack\"))\n        return \"goBack\"; ¦     if (false)\n        return \"goBack\";"
"hidden digits take + ¦ qml/js/Stk.js ¦ return request && request.hideTyping ? \"0123456789*#\" : \"0123456789*#+\"; ¦ return \"0123456789*#+\";"
"lengths in UTF-16 units ¦ qml/js/Stk.js ¦             if (d >= 0xdc00 && d <= 0xdfff)\n                i++; ¦             if (false)\n                i++;"
"quick digit takes + ¦ qml/js/Stk.js ¦         return \"0123456789*#\";\n    return \"\"; ¦         return \"0123456789*#+\";\n    return \"\";"
"older request wins ¦ qml/js/Stk.js ¦         if (requests[i].requestId > best.requestId) ¦         if (requests[i].requestId < best.requestId)"
"same SIM not replaced ¦ qml/js/Stk.js ¦ return x.requestId !== r.requestId && x.simId !== r.simId; ¦ return x.requestId !== r.requestId;"
"timeout not told ¦ qml/js/Stk.js ¦         return \"The SIM card stopped waiting for an answer.\"; ¦         return \"\";"
"old telephonyd taken for an error ¦ qml/js/Stk.js ¦     return /unknown method|not implemented/i.test(errorText || \"\"); ¦     return false;"
"ended request stays ¦ qml/StkService.qml ¦             requests = Stk.without(requests, r.ended.requestId); ¦             requests = requests;"
"answered request stays until ended ¦ qml/StkService.qml ¦                      stk.requests = Stk.without(stk.requests, id);\n                 }, ¦                 },"
"no retry ¦ qml/StkService.qml ¦             retryTimer.restart(); ¦             retryTimer.stop();"
"selection loses the SIM ¦ qml/StkService.qml ¦             args.simId = menu.simId; ¦             args.simId = undefined;"
"menu item sends its row ¦ qml/MenuPage.qml ¦ onClicked: page.stk.selectItem(modelData.index) ¦ onClicked: page.stk.selectItem(0)"
"back gesture ignored ¦ qml/RequestView.qml ¦             answered(Stk.backAction(request), undefined); ¦             answered(\"answer\", undefined);"
"quick digit waits for OK ¦ qml/RequestView.qml ¦                     if (parent.quick && Stk.acceptsKey(view.request, text) && !view.busy) ¦                     if (false)"
"no is yes ¦ qml/RequestView.qml ¦                     onClicked: view.answer(false) ¦                     onClicked: view.answer(true)"
"typing shown for a hidden entry ¦ qml/RequestView.qml ¦ echoMode: view.request && view.request.hideTyping ? TextInput.Password : TextInput.Normal ¦ echoMode: TextInput.Normal"
"OK while too short ¦ qml/RequestView.qml ¦                 enabled: parent.check.ok && !view.busy ¦                 enabled: !view.busy"
"default item not marked ¦ qml/RequestView.qml ¦ currentIndex: view.request && view.request.defaultItem >= 0 ? view.request.defaultItem : -1 ¦ currentIndex: -1"
)

failures=0
for m in "${mutations[@]}"; do
    what=${m%% ¦ *}; rest=${m#* ¦ }
    file=${rest%% ¦ *}; rest=${rest#* ¦ }
    from=$(printf '%b' "${rest%% ¦ *}")
    to=$(printf '%b' "${rest#* ¦ }")
    cp "$file" "$SAVE/original"
    current=$file
    if ! FROM="$from" TO="$to" python3 -I -c '
import os, sys
p = sys.argv[1]; s = open(p).read(); a = os.environ["FROM"]
if s.count(a) != 1:
    sys.exit("not found once: " + a)
open(p, "w").write(s.replace(a, os.environ["TO"]))' "$file"; then
        echo "BAD  $what: the text to change is not in $file"
        failures=$((failures + 1)); restore; continue
    fi
    if tools/run-tests.sh "$LC" > "$SAVE/out" 2>&1; then
        echo "MISS $what: the tests still pass"
        failures=$((failures + 1))
    else
        echo "ok   $what: $(grep -cE '^FAIL|^FAIL!' "$SAVE/out") failing"
    fi
    restore
done
tools/run-tests.sh "$LC" > "$SAVE/out" 2>&1 || { echo "the tests fail on the unchanged tree"; exit 1; }
echo "$([ $failures = 0 ] && echo PASS || echo "FAILED: $failures") - ${#mutations[@]} mutations"
exit $failures
