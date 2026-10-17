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

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Forms 1.0

/*
 * The SIM card's main menu. Tapping an entry starts that application on the
 * SIM card; what it asks then comes up over this page.
 */
AppPage {
    id: page

    objectName: "menuPage"
    // The SIM card names its menu (an operator's name, "SIM services")
    title: stk.menu && stk.menu.title ? stk.menu.title : "SIM Toolkit"

    readonly property var stk: appWindow.stk
    readonly property var items: stk.menu && stk.menu.items ? stk.menu.items : []

    // Why there is no list, or "" when there is one.
    readonly property string emptyText: {
        switch (stk.status) {
        case "loading":
            return "Asking the SIM card…";
        case "unsupported":
            return "This version of the telephony service has no SIM toolkit support.";
        case "denied":
            return "SIM Toolkit may not use the telephony service.";
        case "error":
            return "The telephony service does not answer.";
        }
        if (!stk.menu.available)
            return "There is no SIM toolkit: no SIM card is in, it is locked, or it has no applications.";
        if (items.length === 0)
            return "The SIM card has no menu.";
        return "";
    }

    explanation: stk.menu.idleModeText ? stk.menu.idleModeText : ""

    Label {
        objectName: "emptyText"
        anchors.centerIn: parent
        width: parent.width - Units.gu(4)
        visible: page.emptyText !== ""
        text: page.emptyText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Colors.secondaryText
        font.pixelSize: FontUtils.sizeToPixels("medium")
    }

    ListView {
        id: list

        objectName: "menuList"
        anchors.fill: parent
        visible: page.emptyText === ""
        clip: true
        model: page.items

        delegate: ItemDelegate {
            objectName: "menuItem" + index
            width: list.width
            text: modelData.label
            enabled: !page.stk.busy
            onClicked: page.stk.selectItem(modelData.index)
        }
    }
}
