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
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import "js/Stk.js" as Stk

/*
 * One request of the SIM card: a choice from a list, a message, a text or
 * digits to type, a single key, a yes or no (a call, a web page, a data
 * connection), or a tone (shown, not played). The back gesture answers
 * "back" where the SIM card offers it, otherwise ends the session.
 */
FocusScope {
    id: view

    property var request: null
    property bool busy: false

    readonly property string kind: Stk.viewFor(request)

    // action: "answer", "goBack", "endSession", "busy" or "cancel"
    signal answered(string action, var value)

    function answer(value) { answered("answer", value); }

    onRequestChanged: {
        if (request)
            forceActiveFocus();
    }

    Keys.onEscapePressed: function(event) {
        if (request) {
            answered(Stk.backAction(request), undefined);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.pageGradientTop }
            GradientStop { position: 1.0; color: Colors.pageGradientBottom }
        }
        // the menu underneath must not get the taps
        MouseArea { anchors.fill: parent }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Units.gu(1)
        spacing: Units.gu(1)

        Label {
            objectName: "requestHeading"
            Layout.fillWidth: true
            visible: text !== ""
            text: Stk.heading(view.request)
            wrapMode: Text.WordWrap
            font.bold: true
            font.pixelSize: FontUtils.sizeToPixels("medium")
            color: Colors.text
        }

        Flickable {
            id: textFlick

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, view.kind === "menu" ? view.height * 0.3
                                                                                   : view.height * 0.6)
            visible: requestText.text !== ""
            contentHeight: requestText.implicitHeight
            clip: true

            Label {
                id: requestText

                objectName: "requestText"
                width: textFlick.width
                text: view.request ? view.request.text : ""
                wrapMode: Text.WordWrap
                color: view.request && view.request.urgent ? Colors.error : Colors.text
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
        }

        Loader {
            id: body

            objectName: "requestBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: {
                switch (view.kind) {
                case "menu": return menuBody;
                case "entry": return entryBody;
                case "key": return keyBody;
                case "confirm": return confirmBody;
                case "tone": return toneBody;
                default: return null;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Units.gu(1)

            Button {
                objectName: "backButton"
                text: "Back"
                visible: Stk.allowed(view.request, "goBack")
                enabled: !view.busy
                onClicked: view.answered("goBack", undefined)
            }
            Button {
                objectName: "endButton"
                text: "End"
                visible: Stk.allowed(view.request, "endSession") && view.kind !== "confirm"
                enabled: !view.busy
                onClicked: view.answered("endSession", undefined)
            }
            Item { Layout.fillWidth: true }
            // "OK" / "Stop" / "Dismiss" for what takes no value
            Button {
                objectName: "okButton"
                visible: view.kind === "text" || view.kind === "tone"
                text: view.kind === "tone" ? (view.request && view.request.type === "loopTone" ? "Stop" : "OK")
                                           : (view.request && view.request.type.indexOf("displayAction") === 0
                                              ? "Dismiss" : "OK")
                enabled: !view.busy
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: view.answer(undefined)
            }
        }
    }

    Component {
        id: menuBody

        ListView {
            id: choices

            objectName: "choiceList"
            clip: true
            model: view.request ? view.request.items : []
            currentIndex: view.request && view.request.defaultItem >= 0 ? view.request.defaultItem : -1

            delegate: ItemDelegate {
                objectName: "choice" + index
                width: choices.width
                text: modelData.label
                highlighted: ListView.isCurrentItem
                enabled: !view.busy
                onClicked: view.answer(modelData.index)
            }
        }
    }

    Component {
        id: entryBody

        ColumnLayout {
            spacing: Units.gu(1)

            readonly property var check: Stk.checkEntry(view.request, field.text)

            FormTextField {
                id: field

                objectName: "entryField"
                Layout.fillWidth: true
                // red only once something is typed
                acceptable: text === "" || parent.check.ok
                text: view.request ? view.request.defaultText || "" : ""
                echoMode: view.request && view.request.hideTyping ? TextInput.Password : TextInput.Normal
                inputMethodHints: view.request && view.request.type === "digits"
                                  ? Qt.ImhDialableCharactersOnly | Qt.ImhNoPredictiveText
                                  : Qt.ImhNoPredictiveText
                maximumLength: view.request && view.request.maxLength !== undefined ? view.request.maxLength : 255
                focus: true
                Component.onCompleted: forceActiveFocus()
                onAccepted: {
                    if (Stk.checkEntry(view.request, text).ok && !view.busy)
                        view.answer(text);
                }
            }

            Label {
                objectName: "entryHint"
                Layout.fillWidth: true
                // nothing typed yet: the limits, not an error
                readonly property bool showError: !parent.check.ok && field.text !== ""
                text: showError ? parent.check.message : limitsText()
                color: showError ? Colors.error : Colors.secondaryText
                wrapMode: Text.WordWrap

                function limitsText() {
                    var r = view.request;
                    if (!r)
                        return "";
                    if (r.minLength === 0)
                        return "Up to " + r.maxLength + (r.maxLength === 1 ? " character" : " characters");
                    if (r.minLength === r.maxLength)
                        return r.maxLength + (r.maxLength === 1 ? " character" : " characters");
                    return r.minLength + " to " + r.maxLength + " characters";
                }
            }

            Button {
                objectName: "entryOkButton"
                Layout.alignment: Qt.AlignRight
                text: "OK"
                enabled: parent.check.ok && !view.busy
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: view.answer(field.text)
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: keyBody

        ColumnLayout {
            spacing: Units.gu(1)

            readonly property bool quick: view.request && view.request.type === "quickDigit"
            readonly property bool ok: Stk.acceptsKey(view.request, keyField.text)

            FormTextField {
                id: keyField

                objectName: "keyField"
                Layout.preferredWidth: Units.gu(10)
                maximumLength: 2
                horizontalAlignment: TextInput.AlignHCenter
                // a quick digit is not shown, and goes out on the key press
                echoMode: parent.quick ? TextInput.Password : TextInput.Normal
                inputMethodHints: Stk.keyCharacters(view.request) !== ""
                                  ? Qt.ImhDialableCharactersOnly | Qt.ImhNoPredictiveText
                                  : Qt.ImhNoPredictiveText
                focus: true
                Component.onCompleted: forceActiveFocus()
                // checked here, not through parent.ok: that binding may not
                // have caught up with the new text yet
                onTextChanged: {
                    if (parent.quick && Stk.acceptsKey(view.request, text) && !view.busy)
                        view.answer(text);
                }
                onAccepted: {
                    if (Stk.acceptsKey(view.request, text) && !view.busy)
                        view.answer(text);
                }
            }

            Label {
                objectName: "keyHint"
                Layout.fillWidth: true
                text: Stk.keyCharacters(view.request) !== "" ? "One digit, * or #" + (parent.quick ? "" : " or +")
                                                             : "One character"
                color: keyField.text !== "" && !parent.ok ? Colors.error : Colors.secondaryText
            }

            Button {
                objectName: "keyOkButton"
                Layout.alignment: Qt.AlignRight
                visible: !parent.quick
                text: "OK"
                enabled: parent.ok && !view.busy
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: view.answer(keyField.text)
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: confirmBody

        ColumnLayout {
            spacing: Units.gu(1)

            readonly property var labels: Stk.confirmLabels(view.request)

            Label {
                objectName: "confirmUrl"
                Layout.fillWidth: true
                visible: text !== ""
                text: view.request && view.request.url ? view.request.url : ""
                wrapMode: Text.WrapAnywhere
                color: Colors.secondaryText
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Units.gu(1)

                Button {
                    objectName: "noButton"
                    Layout.fillWidth: true
                    text: parent.parent.labels.no
                    enabled: !view.busy
                    // The way out, left of Yes: the default light button;
                    // answering No destroys nothing, and red is for
                    // destructive actions only (webOS).
                    LuneOSButton.mainColor: LuneOSButton.secondaryColor
                    onClicked: view.answer(false)
                }
                Button {
                    objectName: "yesButton"
                    Layout.fillWidth: true
                    text: parent.parent.labels.yes
                    enabled: !view.busy
                    LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                    onClicked: view.answer(true)
                }
            }
        }
    }

    Component {
        id: toneBody

        ColumnLayout {
            Label {
                objectName: "toneLabel"
                Layout.fillWidth: true
                text: "Tone: " + Stk.toneLabel(view.request ? view.request.tone : "")
                      + (view.request && view.request.type === "loopTone" ? " (repeating)" : "")
                color: Colors.secondaryText
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
        }
    }
}
