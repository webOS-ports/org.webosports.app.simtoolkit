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
import QtQuick.Controls

import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0

/*
 * SIM Toolkit: the menu of the SIM card's own applications (balance, top-up,
 * operator services), and whatever the SIM card asks while one runs - a
 * choice, a message, a code to type, a yes or no.
 *
 * telephonyd talks to the SIM card; this app only shows its menu and its
 * requests and sends the answers back. When the SIM card asks something
 * while the app is closed, telephonyd starts it.
 */
AppWindow {
    id: appWindow

    title: "SIM Toolkit"
    icon: Qt.resolvedUrl("../icon.png")
    initialPage: Qt.resolvedUrl("MenuPage.qml")

    // The bus; the tests hand in a fake.
    property var bus: lunaService

    property alias stk: stkService
    property alias requestView: requestView
    property string notice: ""

    LunaService {
        id: lunaService
        name: "org.webosports.app.simtoolkit"
    }

    StkService {
        id: stkService
        bus: appWindow.bus
        onNotice: function(text) { appWindow.notice = text; }

        // A request while the card is in the background: bring it up, the
        // SIM card is waiting for an answer.
        onRequestChanged: {
            if (request) {
                appWindow.notice = "";
                if (Qt.application.state !== Qt.ApplicationActive && typeof appWindow.raise === "function")
                    appWindow.raise();
            }
        }
    }

    Component.onCompleted: stkService.start()

    // Opening a web page the SIM card offered; needs "appmanager.management".
    AppLauncher {
        id: launcher
        clientName: "org.webosports.app.simtoolkit"
    }

    function openUrl(url) {
        if (url)
            launcher.open(url, undefined, function(error) { appWindow.notice = "Could not open " + url + ": " + error; });
    }

    // telephonyd starts the app with {"stkRequestId": n}; the request itself
    // comes over the subscription, so there is nothing else to do.
    LaunchParams {
        window: appWindow
    }

    // Under the header: what went wrong, until dismissed.
    Item {
        width: appWindow.width
        height: statusNotice.visible ? statusNotice.height + Units.gu(2) : 0

        StatusNotice {
            id: statusNotice

            objectName: "statusNotice"
            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            visible: text !== ""
            text: appWindow.notice
            onDismissed: appWindow.notice = ""
        }
    }

    // What the SIM card asks, over the menu while it waits.
    RequestView {
        id: requestView

        objectName: "requestView"
        parent: appWindow.pageStack
        anchors.fill: parent
        z: 10
        request: stkService.request
        busy: stkService.busy
        visible: request !== null

        onAnswered: function(action, value) {
            var r = request;
            stkService.respond(r, action, value);
            if (r.type === "confirmLaunchBrowser" && action === "answer" && value === true)
                appWindow.openUrl(r.url);
        }
    }
}
