/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtTest

import "../../qml/js/Stk.js" as Stk

/*
 * qml/js/Stk.js: views, answer checks and the back gesture, in QML's own
 * engine.
 */
TestCase {
    name: "StkLogic"

    function req(type, extra) {
        return Object.assign({ requestId: 1, simId: 0, type: type, text: "",
                               allowed: { goBack: true, endSession: true, busy: false } }, extra || {});
    }

    function test_every_type_has_a_view() {
        var types = ["selection", "displayText", "input", "digits", "key", "digit", "quickDigit",
                     "confirmation", "confirmCallSetup", "confirmLaunchBrowser", "confirmOpenChannel",
                     "playTone", "loopTone", "displayActionInformation", "displayAction"];
        compare(types.length, 15);
        for (var i = 0; i < types.length; i++)
            verify(Stk.viewFor(req(types[i])) !== "unknown", types[i]);
        compare(Stk.viewFor(req("somethingNew")), "unknown");
        compare(Stk.viewFor(null), "unknown");
        compare(Stk.viewFor(req("selection")), "menu");
        compare(Stk.viewFor(req("digits")), "entry");
        compare(Stk.viewFor(req("quickDigit")), "key");
        compare(Stk.viewFor(req("confirmOpenChannel")), "confirm");
        compare(Stk.viewFor(req("loopTone")), "tone");
    }

    function test_back_action() {
        compare(Stk.backAction(req("input")), "goBack");
        compare(Stk.backAction(req("confirmCallSetup", { allowed: { goBack: false, endSession: true } })),
                "endSession");
        compare(Stk.backAction(req("confirmLaunchBrowser", { allowed: { goBack: false, endSession: false } })),
                "cancel");
        compare(Stk.backAction(req("x", { allowed: undefined })), "cancel");
    }

    function test_entry_lengths() {
        var r = req("input", { minLength: 2, maxLength: 4 });
        verify(!Stk.checkEntry(r, "a").ok);
        compare(Stk.checkEntry(r, "a").message, "Enter at least 2 characters");
        verify(Stk.checkEntry(r, "ab").ok);
        verify(Stk.checkEntry(r, "abcd").ok);
        verify(!Stk.checkEntry(r, "abcde").ok);
        compare(Stk.checkEntry(r, "abcde").message, "At most 4 characters");
        // characters, not UTF-16 units: one emoji is one character
        verify(Stk.checkEntry(req("input", { minLength: 1, maxLength: 1 }), "😀").ok);
        compare(Stk.characterCount("😀a"), 2);
        compare(Stk.checkEntry(req("input", { minLength: 1, maxLength: 3 }), "").message,
                "Enter at least 1 character");
    }

    function test_digits() {
        var r = req("digits", { minLength: 1, maxLength: 8 });
        verify(Stk.checkEntry(r, "12*#+").ok);
        verify(!Stk.checkEntry(r, "12a").ok);
        compare(Stk.checkEntry(r, "12a").message, "Only digits, *, # and +");
        var hidden = req("digits", { minLength: 4, maxLength: 4, hideTyping: true });
        verify(!Stk.checkEntry(hidden, "12+4").ok);
        compare(Stk.checkEntry(hidden, "12+4").message, "Only digits, * and #");
        verify(Stk.checkEntry(hidden, "1234").ok);
    }

    function test_keys() {
        verify(Stk.acceptsKey(req("key"), "x"));
        verify(Stk.acceptsKey(req("key"), "ä"));
        verify(!Stk.acceptsKey(req("key"), "xy"));
        verify(!Stk.acceptsKey(req("key"), ""));
        verify(Stk.acceptsKey(req("digit"), "+"));
        verify(!Stk.acceptsKey(req("digit"), "a"));
        verify(Stk.acceptsKey(req("quickDigit"), "#"));
        verify(!Stk.acceptsKey(req("quickDigit"), "+"));
    }

    function test_labels() {
        compare(Stk.confirmLabels(req("confirmCallSetup")).yes, "Call");
        compare(Stk.confirmLabels(req("confirmation")).no, "No");
        compare(Stk.toneLabel("ringing-tone"), "Ringing tone");
        compare(Stk.toneLabel("made-up"), "Tone");
        verify(Stk.heading(req("confirmOpenChannel")).indexOf("data connection") > 0);
        compare(Stk.heading(req("selection")), "");
    }

    function test_request_list() {
        var a = req("input", { requestId: 3, simId: 0 });
        var b = req("input", { requestId: 5, simId: 1 });
        var c = req("displayText", { requestId: 7, simId: 0 });
        compare(Stk.current([]), null);
        compare(Stk.current([a, b]).requestId, 5);
        var list = Stk.withRequest([a, b], c);
        // c replaces a: one per SIM
        compare(list.length, 2);
        compare(Stk.current(list).requestId, 7);
        compare(Stk.without(list, 7).length, 1);
        compare(Stk.without(list, 7)[0].requestId, 5);
    }

    function test_messages() {
        verify(Stk.endedMessage("timeout") !== "");
        compare(Stk.endedMessage("answered"), "");
        compare(Stk.endedMessage("cancelled"), "");
        verify(Stk.isUnsupported("Unknown method \"stkGetMainMenu\" for category \"/\""));
        verify(!Stk.isUnsupported("Denied method call"));
        verify(!Stk.isUnsupported(""));
    }
}
