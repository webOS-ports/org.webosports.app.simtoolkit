/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick

/*
 * telephonyd's SIM toolkit methods as the app sees them over LunaService:
 * call() and subscribe() with string arguments and {payload} replies. The
 * tests set what it answers and push requests and their ends through the
 * subscription the app made.
 */
QtObject {
    id: fake

    // every call and subscribe: { uri, method, args }
    property var calls: []
    property var subs: ({})

    property var menuReply: ({ "returnValue": true, "simId": 0, "available": true, "title": "Operator",
                               "iconId": 0, "idleModeText": "",
                               "items": [ { "index": 0, "label": "Balance", "iconId": 0 },
                                          { "index": 1, "label": "Top up", "iconId": 0 } ] })
    property var initialRequests: []
    // errorText the subscriptions fail with, "" for none
    property string failWith: ""
    // what stkRespond / stkSelectItem answer; null means success
    property var respondReply: null
    property var selectReply: null

    function _method(uri) {
        return uri.substring(uri.lastIndexOf("/") + 1);
    }

    function _send(callback, object) {
        callback({ "payload": JSON.stringify(object) });
    }

    function subscribe(uri, args, onResponse, onError) {
        var method = _method(uri);
        calls.push({ "uri": uri, "method": method, "args": JSON.parse(args) });
        var sub = { "onResponse": onResponse, "onError": onError, "cancelled": false };
        sub.cancel = function() { sub.cancelled = true; };
        subs[method] = sub;

        if (failWith !== "") {
            _send(onResponse, { "returnValue": false, "errorText": failWith });
            return sub;
        }
        if (method === "stkGetMainMenu")
            _send(onResponse, menuReply);
        else if (method === "stkAgentRequest")
            _send(onResponse, { "returnValue": true, "subscribed": true, "requests": initialRequests });
        return sub;
    }

    function call(uri, args, onResponse, onError) {
        var method = _method(uri);
        calls.push({ "uri": uri, "method": method, "args": JSON.parse(args) });
        if (method === "stkRespond")
            _send(onResponse, respondReply || { "returnValue": true });
        else if (method === "stkSelectItem")
            _send(onResponse, selectReply || { "returnValue": true, "simId": 0 });
        else
            _send(onResponse, { "returnValue": true });
    }

    function callsTo(method) {
        return calls.filter(function(c) { return c.method === method; });
    }

    function lastCall(method) {
        var list = callsTo(method);
        return list.length ? list[list.length - 1] : null;
    }

    // telephonyd posting to the subscribers
    function pushRequest(request) {
        _send(subs.stkAgentRequest.onResponse, { "returnValue": true, "event": "request", "request": request });
    }

    function endRequest(requestId, reason) {
        _send(subs.stkAgentRequest.onResponse,
              { "returnValue": true, "event": "ended",
                "ended": { "requestId": requestId, "simId": 0, "type": "x", "reason": reason } });
    }

    function setMenu(menu) {
        menuReply = menu;
        _send(subs.stkGetMainMenu.onResponse, menu);
    }

    // the subscription dropping, as when telephonyd goes away
    function dropSubscriptions(errorText) {
        _send(subs.stkAgentRequest.onResponse, { "returnValue": false, "errorText": errorText });
    }
}
