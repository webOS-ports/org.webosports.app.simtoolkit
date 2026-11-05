#!/bin/sh
# Runs the QML tests on the build host, with luneos-components' desktop
# stand-ins and FakeStkBus.qml for telephonyd:
#
#   tests/qml/tst_logic.qml        qml/js/Stk.js in QML's own engine
#   tests/qml/tst_ui.qml           the app itself
#   tests/screens/tst_screens.qml  every screen of the app, once per device
#                                  in PROFILES (default: mindphone 480x800,
#                                  q25 720x720, tp 1024x768, radon 720x1600),
#                                  saved as
#                                  build/test-output/ui/<profile>-<screen>.png
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and the LuneOS.Components plugin. QML_TESTS=<file>
# runs one file of tests/qml (QML_TESTS= none); PROFILES= skips the screens.
#
# The stand-ins read their profile (and with it the grid unit) once, as
# they load, and qmltestrunner takes no --profile, so each profile runs
# against a copy of LunaNext.Common whose default profile is that device.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
PROFILES=${PROFILES-mindphone q25 tp radon}
# Throwaway settings and cache, under build/ rather than the user's.
mkdir -p build/test-output/ui
CONF=$(mktemp -d "$PWD/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF"' EXIT

run() {
    rm -rf "$CONF/config" "$CONF/cache"
    XDG_CONFIG_HOME=$CONF/config XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
    QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} "$@"
}

status=0
if [ -n "${QML_TESTS-tests/qml}" ]; then
    run -import "$LC/modules" -import "$LC/test/imports" -input "${QML_TESTS:-tests/qml}" "$@" || status=1
fi
for profile in $PROFILES; do
    common=$CONF/profile-$profile/LunaNext/Common
    mkdir -p "$common"
    cp "$LC"/test/imports/LunaNext/Common/* "$common/"
    sed -i "s/^var defaultProfile = .*/var defaultProfile = \"$profile\";/" "$common/SettingsStub.js"
    grep -q "^var defaultProfile = \"$profile\";" "$common/SettingsStub.js"
    echo "--- screens: $profile"
    # the last -import wins, so the copy goes after the stand-ins
    rm -f build/test-output/ui/"$profile"-*.png
    run -import "$LC/modules" -import "$LC/test/imports" -import "$CONF/profile-$profile" \
        -input tests/screens/tst_screens.qml "$@" || status=1
    if ! ls build/test-output/ui/"$profile"-*.png >/dev/null 2>&1; then
        echo "FAIL! : screens did not run as $profile" >&2
        status=1
    fi
done
exit $status
