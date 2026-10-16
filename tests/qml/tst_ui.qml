/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtQuick.Controls
import QtTest

/*
 * The app - qml/main.qml with its pages - on the build host, with
 * luneos-components' desktop stand-ins for the window and FakeStkBus.qml
 * for telephonyd. Run by tests/run-qml-tests.sh.
 */
TestCase {
    id: test
    name: "SimToolkitUi"
    when: windowShown

    property var app: null
    property var bus: null

    function makeBus(props) {
        var component = Qt.createComponent(Qt.resolvedUrl("FakeStkBus.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        bus = component.createObject(test, props || {});
        return bus;
    }

    function createApp(busProps, width, height) {
        makeBus(busProps);
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        app = component.createObject(null, { bus: bus });
        verify(app !== null, "main.qml did not load");
        app.width = width || 480;
        app.height = height || 800;
        waitForRendering(app.contentItem);
        return app;
    }

    function cleanup() {
        if (app) {
            app.destroy();
            app = null;
        }
        if (bus) {
            bus.destroy();
            bus = null;
        }
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function page() {
        return app.pageStack.currentItem;
    }

    function view() {
        return app.requestView;
    }

    function inView(objectName) {
        return findChild(view(), objectName);
    }

    function req(id, type, extra) {
        return Object.assign({ requestId: id, simId: 0, type: type, session: true, text: "Text " + id,
                               iconId: 0, answer: "none",
                               allowed: { goBack: true, endSession: true, busy: false } }, extra || {});
    }

    function lastRespond() {
        var c = bus.lastCall("stkRespond");
        verify(c !== null, "no stkRespond");
        return c.args;
    }

    // ------------------------------------------------------------------

    function test_subscribes_on_start() {
        createApp();
        compare(bus.callsTo("stkGetMainMenu").length, 1);
        compare(bus.callsTo("stkAgentRequest").length, 1);
        compare(bus.lastCall("stkAgentRequest").args.subscribe, true);
        compare(bus.lastCall("stkAgentRequest").uri, "luna://com.webos.service.telephony/stkAgentRequest");
    }

    function test_menu_shows_and_selects() {
        createApp();
        compare(page().title, "Operator");
        var list = findChild(page(), "menuList");
        verify(list.visible);
        compare(list.count, 2);
        verify(!findChild(page(), "emptyText").visible);
        verify(!view().visible);

        var item = findChild(list, "menuItem1");
        verify(item);
        compare(item.text, "Top up");
        mouseClick(item);
        var c = bus.lastCall("stkSelectItem");
        verify(c !== null);
        compare(c.args.index, 1);
        compare(c.args.simId, 0);
    }

    function test_menu_updates() {
        createApp();
        bus.setMenu({ returnValue: true, simId: 0, available: true, title: "New", iconId: 0, idleModeText: "Idle text",
                      items: [{ index: 0, label: "Only", iconId: 0 }] });
        compare(page().title, "New");
        compare(findChild(page(), "menuList").count, 1);
        compare(page().explanation, "Idle text");
    }

    function test_no_toolkit() {
        createApp({ menuReply: { returnValue: true, simId: 0, available: false, title: "", items: [] } });
        verify(findChild(page(), "emptyText").visible);
        verify(findChild(page(), "emptyText").text.indexOf("no SIM card") >= 0);
        verify(!findChild(page(), "menuList").visible);
        compare(page().title, "SIM Toolkit");
    }

    function test_old_telephonyd() {
        createApp({ failWith: "Unknown method \"stkGetMainMenu\" for category \"/\"" });
        compare(app.stk.status, "unsupported");
        verify(findChild(page(), "emptyText").text.indexOf("no SIM toolkit support") >= 0);
    }

    function test_denied() {
        createApp({ failWith: "Denied method call \"stkGetMainMenu\" for category \"/\"" });
        compare(app.stk.status, "denied");
        verify(findChild(page(), "emptyText").text.indexOf("may not use") >= 0);
    }

    function test_resubscribes_after_failure() {
        createApp();
        app.stk.retryDelay = 50;
        bus.dropSubscriptions("Service is not running");
        compare(app.stk.status, "error");
        tryCompare(app.stk, "status", "ready", 2000);
        compare(bus.callsTo("stkAgentRequest").length, 2);
    }

    function test_pending_request_shown_at_start() {
        createApp({ initialRequests: [req(4, "displayText", { text: "Welcome" })] });
        verify(view().visible);
        compare(inView("requestText").text, "Welcome");
    }

    function test_display_text_ok() {
        createApp();
        bus.pushRequest(req(1, "displayText", { text: "Your balance is 5", allowed: { goBack: true, endSession: true, busy: true } }));
        verify(view().visible);
        compare(inView("requestText").text, "Your balance is 5");
        verify(inView("okButton").visible);
        mouseClick(inView("okButton"));
        compare(lastRespond().requestId, 1);
        compare(lastRespond().action, "answer");
        verify(lastRespond().value === undefined);
        // answered: back to the menu without waiting for "ended"
        verify(!view().visible);
    }

    function test_selection() {
        createApp();
        bus.pushRequest(req(2, "selection", { text: "Sports", answer: "index", defaultItem: 1,
                                               items: [{ index: 0, label: "Chess", iconId: 0 },
                                                       { index: 1, label: "Golf", iconId: 0 }] }));
        var list = inView("choiceList");
        verify(list);
        compare(list.count, 2);
        compare(list.currentIndex, 1);
        mouseClick(findChild(list, "choice0"));
        compare(lastRespond().value, 0);
        compare(lastRespond().action, "answer");
    }

    function test_input_limits() {
        createApp();
        bus.pushRequest(req(3, "input", { text: "Name", answer: "string", defaultText: "", minLength: 2,
                                          maxLength: 4, hideTyping: false }));
        var field = inView("entryField");
        var ok = inView("entryOkButton");
        verify(field && ok);
        compare(field.echoMode, TextInput.Normal);
        verify(!ok.enabled);
        // empty: the limits, not an error yet
        compare(inView("entryHint").text, "2 to 4 characters");
        field.text = "a";
        verify(inView("entryHint").text.indexOf("at least 2") >= 0);
        verify(!field.acceptable);
        field.text = "ab";
        verify(field.acceptable);
        verify(ok.enabled);
        compare(inView("entryHint").text, "2 to 4 characters");
        field.text = "abcd";
        mouseClick(ok);
        compare(lastRespond().value, "abcd");
    }

    function test_digits_hidden() {
        createApp();
        bus.pushRequest(req(4, "digits", { text: "PIN", answer: "string", defaultText: "", minLength: 4,
                                           maxLength: 4, hideTyping: true }));
        var field = inView("entryField");
        compare(field.echoMode, TextInput.Password);
        field.text = "12+4";
        verify(!inView("entryOkButton").enabled);
        compare(inView("entryHint").text, "Only digits, * and #");
        field.text = "1234";
        verify(inView("entryOkButton").enabled);
        // Enter answers as well
        field.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(lastRespond().value, "1234");
    }

    function test_default_text() {
        createApp();
        bus.pushRequest(req(5, "input", { answer: "string", defaultText: "abc", minLength: 0, maxLength: 10 }));
        compare(inView("entryField").text, "abc");
    }

    function test_quick_digit_sends_on_key() {
        createApp();
        bus.pushRequest(req(6, "quickDigit", { answer: "string" }));
        var field = inView("keyField");
        verify(field);
        verify(!inView("keyOkButton").visible);
        field.text = "+";
        compare(bus.callsTo("stkRespond").length, 0);
        field.text = "7";
        compare(lastRespond().value, "7");
    }

    function test_key() {
        createApp();
        bus.pushRequest(req(7, "key", { answer: "string" }));
        var field = inView("keyField");
        field.text = "xy";
        verify(!inView("keyOkButton").enabled);
        field.text = "y";
        mouseClick(inView("keyOkButton"));
        compare(lastRespond().value, "y");
    }

    function test_confirm_call() {
        createApp();
        bus.pushRequest(req(8, "confirmCallSetup", { text: "Call 1194?", answer: "boolean",
                                                     allowed: { goBack: false, endSession: true, busy: false } }));
        compare(inView("yesButton").text, "Call");
        verify(!inView("backButton").visible);
        // "No" is the way out here, no separate End
        verify(!inView("endButton").visible);
        mouseClick(inView("noButton"));
        compare(lastRespond().value, false);
    }

    function test_confirm_browser() {
        createApp();
        bus.pushRequest(req(9, "confirmLaunchBrowser", { text: "Open?", answer: "boolean", url: "http://example.com/",
                                                         allowed: { goBack: false, endSession: false, busy: false } }));
        compare(inView("confirmUrl").text, "http://example.com/");
        mouseClick(inView("yesButton"));
        compare(lastRespond().value, true);
    }

    function test_confirm_channel() {
        createApp();
        bus.pushRequest(req(10, "confirmOpenChannel", { answer: "boolean",
                                                        allowed: { goBack: false, endSession: true, busy: false } }));
        verify(inView("requestHeading").text.indexOf("data connection") > 0);
        compare(inView("yesButton").text, "Allow");
        mouseClick(inView("yesButton"));
        compare(lastRespond().value, true);
    }

    function test_tone_is_a_notice() {
        createApp();
        bus.pushRequest(req(11, "loopTone", { text: "Ringing", tone: "ringing-tone",
                                              allowed: { goBack: false, endSession: true, busy: false } }));
        compare(inView("toneLabel").text, "Tone: Ringing tone (repeating)");
        compare(inView("okButton").text, "Stop");
        mouseClick(inView("okButton"));
        compare(lastRespond().action, "answer");
    }

    function test_end_button() {
        createApp();
        bus.pushRequest(req(12, "input", { answer: "string", minLength: 1, maxLength: 5 }));
        verify(inView("endButton").visible);
        mouseClick(inView("endButton"));
        compare(lastRespond().action, "endSession");
    }

    function test_back_gesture_goes_back() {
        createApp();
        bus.pushRequest(req(13, "selection", { answer: "index", items: [{ index: 0, label: "A", iconId: 0 }] }));
        verify(view().activeFocus);
        keyClick(Qt.Key_Escape);
        compare(lastRespond().action, "goBack");
    }

    function test_back_gesture_from_a_text_field() {
        createApp();
        bus.pushRequest(req(14, "input", { answer: "string", minLength: 1, maxLength: 5 }));
        tryVerify(function() { return inView("entryField").activeFocus; });
        keyClick(Qt.Key_Escape);
        compare(lastRespond().action, "goBack");
    }

    function test_back_gesture_ends_where_no_back() {
        createApp();
        bus.pushRequest(req(15, "playTone", { tone: "general-beep",
                                              allowed: { goBack: false, endSession: true, busy: false } }));
        keyClick(Qt.Key_Escape);
        compare(lastRespond().action, "endSession");
    }

    function test_back_gesture_declines_browser() {
        createApp();
        bus.pushRequest(req(16, "confirmLaunchBrowser", { answer: "boolean", url: "http://example.com/",
                                                          allowed: { goBack: false, endSession: false, busy: false } }));
        keyClick(Qt.Key_Escape);
        compare(lastRespond().action, "cancel");
    }

    function test_ended_by_sim_and_timeout_notice() {
        createApp();
        bus.pushRequest(req(17, "input", { answer: "string", minLength: 1, maxLength: 5 }));
        verify(view().visible);
        bus.endRequest(17, "timeout");
        verify(!view().visible);
        verify(app.notice.indexOf("stopped waiting") >= 0);
        verify(findChild(app.contentItem, "statusNotice").visible);
    }

    function test_cancelled_quietly() {
        createApp();
        bus.pushRequest(req(18, "displayText"));
        bus.endRequest(18, "cancelled");
        verify(!view().visible);
        compare(app.notice, "");
    }

    function test_refused_answer_keeps_request() {
        createApp({ respondReply: { returnValue: false, errorText: "Input length out of range" } });
        bus.pushRequest(req(19, "displayText"));
        mouseClick(inView("okButton"));
        verify(view().visible);
        compare(app.notice, "Input length out of range");
    }

    function test_stale_request_dropped() {
        createApp({ respondReply: { returnValue: false, errorText: "No such request" } });
        bus.pushRequest(req(20, "displayText"));
        mouseClick(inView("okButton"));
        verify(!view().visible);
    }

    function test_newer_request_replaces_older_of_same_sim() {
        createApp();
        bus.pushRequest(req(21, "displayText", { text: "first" }));
        bus.pushRequest(req(22, "displayText", { text: "second" }));
        compare(inView("requestText").text, "second");
        compare(app.stk.requests.length, 1);
    }

    function test_two_sims_one_after_the_other() {
        createApp();
        bus.pushRequest(req(23, "displayText", { text: "SIM 1", simId: 0 }));
        bus.pushRequest(req(24, "displayText", { text: "SIM 2", simId: 1 }));
        compare(inView("requestText").text, "SIM 2");
        mouseClick(inView("okButton"));
        compare(lastRespond().requestId, 24);
        compare(inView("requestText").text, "SIM 1");
    }

    function test_select_refused() {
        createApp({ selectReply: { returnValue: false, errorText: "A SIM toolkit session is already running" } });
        mouseClick(findChild(findChild(page(), "menuList"), "menuItem0"));
        compare(app.notice, "A SIM toolkit session is already running");
    }

    function test_square_screen() {
        // the Q25's 720x720 at its scale
        createApp(undefined, 360, 360);
        bus.pushRequest(req(25, "selection", { answer: "index",
                                               items: [{ index: 0, label: "A", iconId: 0 },
                                                       { index: 1, label: "B", iconId: 0 }] }));
        var list = inView("choiceList");
        verify(list.height > 0, "no room for the choices");
        verify(list.y + list.height <= view().height);
    }
}
