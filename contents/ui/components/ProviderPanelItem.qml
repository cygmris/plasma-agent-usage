/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Compact panel representation for ONE provider.
    Pure presentation: input a UsageModel + panelStyle. No data fetching.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../lib/usage.js" as Usage

RowLayout {
    id: panelItem

    // A UsageModel (see lib/usage.js)
    property var model
    property string panelStyle: "text"
    property bool showIcon: true
    property bool vertical: false
    property string iconPath: ""

    spacing: Kirigami.Units.smallSpacing

    readonly property string state: model ? model.state : Usage.STATE.loading
    readonly property bool hasError: state === Usage.STATE.tokenError
        || state === Usage.STATE.rateLimited
        || state === Usage.STATE.error
        || state === Usage.STATE.notLoggedIn
    readonly property bool dimmed: state === Usage.STATE.tokenError || state === Usage.STATE.rateLimited
    readonly property bool isStale: model ? model.isStale === true : false
    readonly property var windows: model && model.windows ? model.windows : []
    // Show numbers only when ok (or ok-with-error overlay states that still keep last values)
    readonly property bool showNumbers: state === Usage.STATE.ok
        || state === Usage.STATE.tokenError
        || state === Usage.STATE.rateLimited

    // Map a semantic color name (from usage.js) to a concrete Kirigami theme color
    function themeColor(name) {
        switch (name) {
        case "positiveTextColor": return Kirigami.Theme.positiveTextColor
        case "neutralTextColor":  return Kirigami.Theme.neutralTextColor
        case "negativeTextColor": return Kirigami.Theme.negativeTextColor
        }
        return Kirigami.Theme.textColor
    }
    function colorFor(percent) {
        return themeColor(Usage.usageColor(percent))
    }
    function itemOpacity() {
        if (panelItem.dimmed) return 0.5
        if (panelItem.isStale) return 0.6
        return 1.0
    }

    // Provider icon with error dot
    Item {
        visible: panelItem.showIcon
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium

        Kirigami.Icon {
            anchors.fill: parent
            source: panelItem.iconPath
        }

        Rectangle {
            visible: panelItem.hasError
            width: 8
            height: 8
            radius: 4
            color: Kirigami.Theme.negativeTextColor
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -2
            anchors.bottomMargin: -2
        }
    }

    // Warning glyph for hard errors (no numbers to show)
    PlasmaComponents.Label {
        visible: panelItem.hasError && !panelItem.showNumbers
        text: "⚠"
        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
        color: Kirigami.Theme.negativeTextColor
    }

    // Per-window renderer
    Repeater {
        model: panelItem.showNumbers ? panelItem.windows : []

        delegate: RowLayout {
            id: winRow
            required property var modelData
            required property int index
            spacing: Kirigami.Units.smallSpacing

            // separator between windows (text style, horizontal only)
            PlasmaComponents.Label {
                visible: winRow.index > 0 && !panelItem.vertical
                    && (panelItem.panelStyle === "text" || !panelItem.panelStyle)
                text: "|"
                opacity: 0.5
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            // === TEXT STYLE ===
            Rectangle {
                visible: panelItem.panelStyle === "text" || !panelItem.panelStyle
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: panelItem.colorFor(winRow.modelData.percent)
                opacity: panelItem.itemOpacity()
            }
            PlasmaComponents.Label {
                visible: panelItem.panelStyle === "text" || !panelItem.panelStyle
                text: Math.round(winRow.modelData.percent) + "%"
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                font.bold: true
                opacity: panelItem.itemOpacity()
            }

            // === CIRCULAR STYLE ===
            Item {
                visible: panelItem.panelStyle === "circular"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                opacity: panelItem.itemOpacity()

                CircularProgress {
                    anchors.fill: parent
                    percent: winRow.modelData.percent
                    progressColor: panelItem.colorFor(winRow.modelData.percent)
                }
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: Math.round(winRow.modelData.percent)
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            // === BAR STYLE ===
            Item {
                visible: panelItem.panelStyle === "bar"
                Layout.preferredWidth: 32
                Layout.preferredHeight: panelItem.height > 0 ? panelItem.height : 24
                opacity: panelItem.itemOpacity()

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 1
                        height: Math.max((parent.height - 2) * Math.min(winRow.modelData.percent / 100, 1), 1)
                        radius: 2
                        color: panelItem.colorFor(winRow.modelData.percent)
                    }
                }
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: Math.round(winRow.modelData.percent)
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }
    }
}
