/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick
import QtTest

import LunaNext.Common 0.1

/*
 * Every screen of the app - the SIM card's menu, the menu's empty and
 * notice states and each kind of request telephonyd hands on - at the
 * window size of one device, with FakeStkBus.qml for telephonyd. Run once
 * per profile by tests/run-qml-tests.sh, which picks the profile; each
 * screen is saved as build/test-output/ui/<profile>-<screen>.png to look
 * at, and checked for the basics that break when a layout does not fit:
 * what matters is visible, has a size and lies inside the window.
 */
TestCase {
    id: test
    name: "SimToolkitScreens"
    when: windowShown

    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    readonly property string profile: Settings.profileName
    property var app: null
    property var bus: null

    function createApp(busProps) {
        var busComponent = Qt.createComponent(Qt.resolvedUrl("../qml/FakeStkBus.qml"));
        if (busComponent.status !== Component.Ready)
            fail(busComponent.errorString());
        bus = busComponent.createObject(test, busProps || {});
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        app = component.createObject(null, { bus: bus });
        verify(app !== null, "main.qml did not load");
        // AppWindow takes the profile's screen
        compare(app.width, Settings.displayWidth);
        compare(app.height, Settings.displayHeight);
        waitForRendering(app.contentItem);
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

    function req(id, type, extra) {
        return Object.assign({ requestId: id, simId: 0, type: type, session: true, text: "",
                               iconId: 0, answer: "none",
                               allowed: { goBack: true, endSession: true, busy: false } }, extra || {});
    }

    // Shown, with a size, and inside the window (no part off screen to the
    // side or below).
    function checkOnScreen(item, what) {
        verify(item, what + " exists");
        verify(item.visible, what + " is visible");
        verify(item.width > 0 && item.height > 0, what + " has a size (" + item.width + "x" + item.height + ")");
        var p = item.mapToItem(app.contentItem, 0, 0);
        verify(p.x >= -0.5 && p.y >= -0.5, what + " starts inside the window at " + p.x + "," + p.y);
        verify(p.x + item.width <= app.width + 0.5,
               what + " ends inside the window: " + (p.x + item.width) + " > " + app.width);
        verify(p.y + item.height <= app.height + 0.5,
               what + " ends above the bottom: " + (p.y + item.height) + " > " + app.height);
    }

    // A label that is meant to wrap: no wider than its box, so no text runs
    // off to the side.
    function checkWraps(label, what) {
        checkOnScreen(label, what);
        verify(label.contentWidth <= label.width + 0.5,
               what + " runs off to the side: " + label.contentWidth + " > " + label.width);
    }

    function inView(objectName) {
        return findChild(app.requestView, objectName);
    }

    function shot(name) {
        var done = false;
        var ok = app.contentItem.grabToImage(function(result) {
            result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        });
        verify(ok, "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
    }

    // A request on screen: the view over the menu, its heading and text,
    // and the buttons that are there.
    function showRequest(request, buttons) {
        createApp();
        bus.pushRequest(request);
        waitForRendering(app.contentItem);
        checkOnScreen(app.requestView, "the request");
        var heading = inView("requestHeading");
        if (heading.visible)
            checkWraps(heading, "the heading");
        if (request.text) {
            // the text scrolls in its box when it is long: the box is on
            // screen, the text no wider than it
            var text = inView("requestText");
            checkOnScreen(text.parent.parent, "the text's box");
            verify(text.contentWidth <= text.width + 0.5, "the text runs off to the side");
        }
        for (var i = 0; i < (buttons || []).length; i++)
            checkOnScreen(inView(buttons[i]), buttons[i]);
    }

    // ------------------------------------------------------------------

    function test_menu() {
        createApp({ menuReply: { returnValue: true, simId: 0, available: true, title: "Operator services",
                                 iconId: 0, idleModeText: "Welcome to your operator",
                                 items: [{ index: 0, label: "Balance", iconId: 0 },
                                         { index: 1, label: "Top up", iconId: 0 },
                                         { index: 2, label: "Roaming and international calling", iconId: 0 },
                                         { index: 3, label: "Operator news", iconId: 0 }] } });
        var page = app.pageStack.currentItem;
        compare(page.objectName, "menuPage");
        checkOnScreen(page, "the menu page");
        var list = findChild(page, "menuList");
        checkOnScreen(list, "the menu");
        compare(list.count, 4);
        for (var i = 0; i < 4; i++)
            checkOnScreen(findChild(list, "menuItem" + i), "menu entry " + i);
        verify(!app.requestView.visible);
        shot("menu");
    }

    function test_no_toolkit() {
        createApp({ menuReply: { returnValue: true, simId: 0, available: false, title: "", items: [] } });
        checkWraps(findChild(app.pageStack.currentItem, "emptyText"), "the no-toolkit text");
        shot("no-toolkit");
    }

    function test_unsupported() {
        createApp({ failWith: "Unknown method \"stkGetMainMenu\" for category \"/\"" });
        checkWraps(findChild(app.pageStack.currentItem, "emptyText"), "the unsupported text");
        shot("unsupported");
    }

    function test_timeout_notice() {
        createApp();
        bus.pushRequest(req(1, "input", { answer: "string", minLength: 1, maxLength: 5 }));
        bus.endRequest(1, "timeout");
        waitForRendering(app.contentItem);
        checkOnScreen(findChild(app.contentItem, "statusNotice"), "the notice");
        checkOnScreen(findChild(app.pageStack.currentItem, "menuList"), "the menu under the notice");
        shot("notice");
    }

    function test_selection() {
        var items = [];
        for (var i = 0; i < 12; i++)
            items.push({ index: i, label: "Choice " + (i + 1), iconId: 0 });
        showRequest(req(2, "selection", { text: "Pick a bundle", answer: "index", defaultItem: 1, items: items }),
                    ["backButton", "endButton"]);
        var list = inView("choiceList");
        checkOnScreen(list, "the choices");
        verify(list.height >= Units.gu(4), "room for at least one choice: " + list.height);
        checkOnScreen(findChild(list, "choice0"), "the first choice");
        shot("selection");
    }

    function test_display_text() {
        showRequest(req(3, "displayText", { text: "Your balance is 5.20 EUR. Your bundle of 2 GB is valid until "
                                                  + "30 November; top up before then to keep it." }),
                    ["okButton", "backButton", "endButton"]);
        shot("display-text");
    }

    function test_display_long_text() {
        var text = "";
        for (var i = 0; i < 80; i++)
            text += "Line " + (i + 1) + " of the operator's terms and conditions. ";
        showRequest(req(4, "displayText", { text: text }), ["okButton"]);
        // a long text scrolls; the buttons stay on screen
        var box = inView("requestText").parent.parent;
        verify(box.contentHeight > box.height, "the long text is in a scrolling box");
        shot("display-long-text");
    }

    function test_input() {
        showRequest(req(5, "input", { text: "Enter your name", answer: "string", defaultText: "Alex",
                                      minLength: 2, maxLength: 20, hideTyping: false }),
                    ["entryOkButton", "backButton", "endButton"]);
        checkOnScreen(inView("entryField"), "the entry field");
        checkWraps(inView("entryHint"), "the hint");
        shot("input");
    }

    function test_digits_hidden() {
        showRequest(req(6, "digits", { text: "Enter your PIN", answer: "string", defaultText: "",
                                       minLength: 4, maxLength: 4, hideTyping: true }),
                    ["entryOkButton"]);
        inView("entryField").text = "12";
        waitForRendering(app.contentItem);
        checkOnScreen(inView("entryField"), "the entry field");
        checkWraps(inView("entryHint"), "the hint");
        shot("digits-hidden");
    }

    function test_key() {
        showRequest(req(7, "key", { text: "Press Y to continue", answer: "string" }), ["keyOkButton"]);
        checkOnScreen(inView("keyField"), "the key field");
        shot("key");
    }

    function test_quick_digit() {
        showRequest(req(8, "quickDigit", { text: "Press 1 for English, 2 for Deutsch", answer: "string" }));
        checkOnScreen(inView("keyField"), "the key field");
        verify(!inView("keyOkButton").visible);
        shot("quick-digit");
    }

    function test_confirm_call() {
        showRequest(req(9, "confirmCallSetup", { text: "Call customer service at 1194?", answer: "boolean",
                                                 allowed: { goBack: false, endSession: true, busy: false } }),
                    ["yesButton", "noButton"]);
        shot("confirm-call");
    }

    function test_confirm_browser() {
        showRequest(req(10, "confirmLaunchBrowser", {
                        text: "Open the operator's page?", answer: "boolean",
                        url: "http://www.example.com/a/rather/long/path/to/the/operator/top-up/page?with=query",
                        allowed: { goBack: false, endSession: false, busy: false } }),
                    ["yesButton", "noButton"]);
        checkWraps(inView("confirmUrl"), "the address");
        shot("confirm-browser");
    }

    function test_confirm_channel() {
        showRequest(req(11, "confirmOpenChannel", { text: "", answer: "boolean",
                                                    allowed: { goBack: false, endSession: true, busy: false } }),
                    ["yesButton", "noButton"]);
        shot("confirm-channel");
    }

    function test_tone() {
        showRequest(req(12, "loopTone", { text: "Ringing", tone: "ringing-tone",
                                          allowed: { goBack: false, endSession: true, busy: false } }),
                    ["okButton"]);
        checkWraps(inView("toneLabel"), "the tone");
        shot("tone");
    }
}
