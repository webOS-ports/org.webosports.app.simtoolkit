/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick

import "js/Stk.js" as Stk

/*
 * telephonyd's SIM toolkit methods:
 *
 *   stkGetMainMenu   (subscribed)  the SIM's menu
 *   stkAgentRequest  (subscribed)  what the SIM asks, as it happens
 *   stkSelectItem                  start a session with a menu item
 *   stkRespond                     answer a request
 *
 * bus is anything with LunaService's call() and subscribe(): the real one
 * on a device, a fake in the tests. When a subscription fails (telephonyd
 * restarted, not up yet) it is made again a little later.
 */
QtObject {
    id: stk

    property var bus: null
    property string serviceUri: "luna://com.webos.service.telephony"

    // "loading", "ready", "unsupported" (a telephonyd without SIM toolkit),
    // "denied" (the app may not call it) or "error"
    property string status: "loading"
    property string errorText: ""

    // { available, title, iconId, items: [{index, label, iconId}], idleModeText, simId }
    property var menu: ({ "available": false, "title": "", "items": [] })

    // pending requests, as stkAgentRequest delivers them
    property var requests: []
    readonly property var request: Stk.current(requests)

    // a selection or an answer is on its way
    property bool busy: false

    // Something to tell the user: an answer that was refused, a request the
    // SIM gave up on.
    signal notice(string text)

    property int retryDelay: 3000
    property var _menuCall: null
    property var _requestCall: null

    function start() {
        if (!bus)
            return;
        _subscribeMenu();
        _subscribeRequests();
    }

    function stop() {
        _cancel(_menuCall);
        _cancel(_requestCall);
        _menuCall = null;
        _requestCall = null;
        retryTimer.stop();
    }

    function _cancel(call) {
        if (call && typeof call.cancel === "function")
            call.cancel();
    }

    function _parse(message) {
        try {
            return JSON.parse(typeof message === "string" ? message : message.payload);
        } catch (e) {
            return { "returnValue": false, "errorText": "Malformed reply" };
        }
    }

    function _failed(errorText) {
        if (Stk.isUnsupported(errorText)) {
            status = "unsupported";
        } else if (/denied/i.test(errorText)) {
            status = "denied";
        } else {
            status = "error";
            retryTimer.restart();
        }
        stk.errorText = errorText;
    }

    function _subscribeMenu() {
        _cancel(_menuCall);
        _menuCall = bus.subscribe(serviceUri + "/stkGetMainMenu", JSON.stringify({ "subscribe": true }),
                                  function(message) {
                                      var r = stk._parse(message);
                                      if (r.returnValue === false) {
                                          stk._failed(r.errorText || "");
                                          return;
                                      }
                                      stk.menu = r;
                                      if (stk.status !== "unsupported" && stk.status !== "denied")
                                          stk.status = "ready";
                                  },
                                  function(message) {
                                      stk._failed(stk._parse(message).errorText || String(message.payload || message));
                                  });
    }

    function _subscribeRequests() {
        _cancel(_requestCall);
        _requestCall = bus.subscribe(serviceUri + "/stkAgentRequest", JSON.stringify({ "subscribe": true }),
                                     function(message) { stk._onRequestMessage(stk._parse(message)); },
                                     function(message) {
                                         stk._failed(stk._parse(message).errorText || String(message.payload || message));
                                     });
    }

    function _onRequestMessage(r) {
        if (r.returnValue === false) {
            _failed(r.errorText || "");
            return;
        }
        if (r.requests !== undefined) {
            // the first reply: what is already waiting
            requests = r.requests;
        } else if (r.event === "request" && r.request) {
            requests = Stk.withRequest(requests, r.request);
        } else if (r.event === "ended" && r.ended) {
            var wasShown = request && request.requestId === r.ended.requestId;
            requests = Stk.without(requests, r.ended.requestId);
            var text = Stk.endedMessage(r.ended.reason);
            if (wasShown && text !== "")
                notice(text);
        }
    }

    function selectItem(index) {
        busy = true;
        var args = { "index": index };
        if (menu && menu.simId !== undefined)
            args.simId = menu.simId;
        bus.call(serviceUri + "/stkSelectItem", JSON.stringify(args),
                 function(message) {
                     stk.busy = false;
                     var r = stk._parse(message);
                     if (r.returnValue === false)
                         stk.notice(r.errorText || "The SIM card did not accept the selection.");
                 },
                 function(message) {
                     stk.busy = false;
                     stk.notice("The SIM card did not accept the selection.");
                 });
    }

    /*
     * Answers request r: action is "answer", "goBack", "endSession", "busy"
     * or "cancel"; value goes with "answer" (an item index, a string, or
     * true/false).
     */
    function respond(r, action, value) {
        if (!r)
            return;
        var args = { "requestId": r.requestId, "action": action };
        if (value !== undefined)
            args.value = value;
        var id = r.requestId;
        busy = true;
        bus.call(serviceUri + "/stkRespond", JSON.stringify(args),
                 function(message) {
                     stk.busy = false;
                     var reply = stk._parse(message);
                     if (reply.returnValue === false) {
                         stk.notice(reply.errorText || "The answer was not accepted.");
                         // gone on the daemon's side already: drop it here too
                         if (/no such request/i.test(reply.errorText || ""))
                             stk.requests = Stk.without(stk.requests, id);
                         return;
                     }
                     // the "ended" event follows; don't keep showing it meanwhile
                     stk.requests = Stk.without(stk.requests, id);
                 },
                 function(message) {
                     stk.busy = false;
                     stk.notice("The answer could not be sent.");
                 });
    }

    // Answers what is on screen for the back gesture.
    function back() {
        if (request)
            respond(request, Stk.backAction(request));
    }

    property Timer _retry: Timer {
        id: retryTimer
        interval: stk.retryDelay
        onTriggered: stk.start()
    }
}
