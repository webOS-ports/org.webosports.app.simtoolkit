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

/*
 * What the app needs to know about a SIM toolkit request, without any UI:
 * which view shows it, which answers it takes, and what the back gesture
 * does. The request objects are telephonyd's stkAgentRequest payloads:
 *
 *   { requestId, simId, type, session, text, iconId,
 *     answer: "none"|"index"|"string"|"boolean",
 *     allowed: { goBack, endSession, busy },
 *     items: [{index, label, iconId}], defaultItem,      (selection)
 *     defaultText, minLength, maxLength, hideTyping,     (input, digits)
 *     urgent, tone, url }
 *
 * The checks mirror what telephonyd (and ofono behind it) accept, so the UI
 * never sends an answer that would be refused.
 */

.pragma library

// The view each request type is shown with.
var VIEWS = {
    "selection": "menu",
    "displayText": "text",
    "input": "entry",
    "digits": "entry",
    "key": "key",
    "digit": "key",
    "quickDigit": "key",
    "confirmation": "confirm",
    "confirmCallSetup": "confirm",
    "confirmLaunchBrowser": "confirm",
    "confirmOpenChannel": "confirm",
    "playTone": "tone",
    "loopTone": "tone",
    "displayActionInformation": "text",
    "displayAction": "text"
};

function viewFor(request) {
    if (!request || !VIEWS.hasOwnProperty(request.type))
        return "unknown";
    return VIEWS[request.type];
}

function allowed(request, what) {
    return !!(request && request.allowed && request.allowed[what]);
}

/*
 * What the back gesture answers: back where the SIM offers it, otherwise
 * the end of the session, otherwise the plain "cancel" (telephonyd turns
 * that into a decline for the few requests that take neither).
 */
function backAction(request) {
    if (allowed(request, "goBack"))
        return "goBack";
    if (allowed(request, "endSession"))
        return "endSession";
    return "cancel";
}

// Characters a digits entry takes; "+" not while the typing is hidden.
function digitCharacters(request) {
    return request && request.hideTyping ? "0123456789*#" : "0123456789*#+";
}

function onlyCharacters(text, allowedChars) {
    for (var i = 0; i < text.length; i++) {
        if (allowedChars.indexOf(text.charAt(i)) < 0)
            return false;
    }
    return true;
}

// Length in characters, counting a surrogate pair once, as ofono does.
function characterCount(text) {
    var n = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
            var d = text.charCodeAt(i + 1);
            if (d >= 0xdc00 && d <= 0xdfff)
                i++;
        }
        n++;
    }
    return n;
}

/*
 * Whether text answers an input / digits request, with why not:
 * { ok: true } or { ok: false, message: "..." }.
 */
function checkEntry(request, text) {
    var min = request.minLength || 0;
    var max = request.maxLength === undefined ? 255 : request.maxLength;
    var len = characterCount(text);

    if (request.type === "digits" && !onlyCharacters(text, digitCharacters(request)))
        return { ok: false, message: request.hideTyping ? "Only digits, * and #"
                                                         : "Only digits, *, # and +" };
    if (len < min)
        return { ok: false, message: min === 1 ? "Enter at least 1 character"
                                               : "Enter at least " + min + " characters" };
    if (len > max)
        return { ok: false, message: "At most " + max + (max === 1 ? " character" : " characters") };
    return { ok: true, message: "" };
}

// The characters a single-key request takes; "" means any one character.
function keyCharacters(request) {
    if (!request)
        return "";
    if (request.type === "digit")
        return "0123456789*#+";
    if (request.type === "quickDigit")
        return "0123456789*#";
    return "";
}

// Whether ch (one typed character) answers a key / digit request.
function acceptsKey(request, ch) {
    if (!ch || characterCount(ch) !== 1)
        return false;
    var set = keyCharacters(request);
    return set === "" || set.indexOf(ch) >= 0;
}

// What the yes button says for each confirmation.
function confirmLabels(request) {
    switch (request && request.type) {
    case "confirmCallSetup":
        return { yes: "Call", no: "Don't call" };
    case "confirmLaunchBrowser":
        return { yes: "Open", no: "Don't open" };
    case "confirmOpenChannel":
        return { yes: "Allow", no: "Don't allow" };
    default:
        return { yes: "Yes", no: "No" };
    }
}

// A heading for requests whose own text may be empty.
function heading(request) {
    switch (request && request.type) {
    case "confirmCallSetup":
        return "The SIM card wants to make a call";
    case "confirmLaunchBrowser":
        return "The SIM card wants to open a web page";
    case "confirmOpenChannel":
        return "The SIM card wants to open a data connection";
    case "playTone":
    case "loopTone":
        return "The SIM card plays a tone";
    case "displayAction":
    case "displayActionInformation":
        return "The SIM card is working";
    default:
        return "";
    }
}

var TONES = {
    "dial-tone": "Dial tone",
    "busy": "Busy",
    "congestion": "Congestion",
    "radio-path-acknowledge": "Radio path acknowledge",
    "radio-path-not-available": "Radio path not available",
    "error": "Error",
    "call-waiting": "Call waiting",
    "ringing-tone": "Ringing tone",
    "general-beep": "Beep",
    "positive-acknowledgement": "Positive acknowledgement",
    "negative-acknowledgement": "Negative acknowledgement",
    "user-ringing-tone": "Ringtone",
    "user-sms-alert": "Message alert",
    "critical": "Critical alert",
    "vibrate": "Vibration",
    "happy": "Happy tone",
    "sad": "Sad tone",
    "urgent-action": "Urgent action",
    "question": "Question",
    "message-received": "Message received"
};

function toneLabel(tone) {
    return TONES.hasOwnProperty(tone) ? TONES[tone] : "Tone";
}

// The answer a "done" button sends for requests that take no value.
function plainAnswer(request) {
    return { requestId: request.requestId, action: "answer" };
}

/*
 * The request to show: the newest pending one. telephonyd keeps one per
 * SIM, so with two SIMs two can be waiting; the newer wins and the other
 * comes back once that one is done.
 */
function current(requests) {
    if (!requests || requests.length === 0)
        return null;
    var best = requests[0];
    for (var i = 1; i < requests.length; i++) {
        if (requests[i].requestId > best.requestId)
            best = requests[i];
    }
    return best;
}

// requests without the one with this id
function without(requests, requestId) {
    return (requests || []).filter(function(r) { return r.requestId !== requestId; });
}

// requests with r added, or replacing an older one for the same SIM
function withRequest(requests, r) {
    var list = (requests || []).filter(function(x) {
        return x.requestId !== r.requestId && x.simId !== r.simId;
    });
    list.push(r);
    return list;
}

// What to tell the user when a request went away without their answer.
function endedMessage(reason) {
    switch (reason) {
    case "timeout":
        return "The SIM card stopped waiting for an answer.";
    case "cancelled":
    case "superseded":
    case "answered":
        return "";
    case "released":
        return "The SIM toolkit session ended.";
    default:
        return "";
    }
}

// The bus' "Unknown method" means a telephony service without SIM toolkit.
function isUnsupported(errorText) {
    return /unknown method|not implemented/i.test(errorText || "");
}
