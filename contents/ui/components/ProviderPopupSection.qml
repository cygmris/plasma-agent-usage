/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Full popup section for ONE provider.
    Pure presentation: input a UsageModel. Actions are emitted as signals
    for main.qml to handle (no command execution here).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../lib/usage.js" as Usage

ColumnLayout {
    id: section

    property var model
    property string iconPath: ""
    // Translation function injected by parent: tr(text) -> string
    property var trFn: (function(t){ return t })

    signal loginRequested()

    spacing: Kirigami.Units.mediumSpacing
    Layout.fillWidth: true

    readonly property string st: model ? model.state : Usage.STATE.loading
    readonly property var windows: model && model.windows ? model.windows : []
    readonly property var models: model && model.models ? model.models : []
    readonly property string plan: model ? (model.plan || "") : ""
    readonly property string displayName: model ? (model.displayName || "") : ""
    readonly property string cliName: model ? (model.id || "") : ""

    function tr(t) { return section.trFn ? section.trFn(t) : t }
    function themeColor(name) {
        switch (name) {
        case "positiveTextColor": return Kirigami.Theme.positiveTextColor
        case "neutralTextColor":  return Kirigami.Theme.neutralTextColor
        case "negativeTextColor": return Kirigami.Theme.negativeTextColor
        }
        return Kirigami.Theme.textColor
    }
    function colorFor(percent) { return themeColor(Usage.usageColor(percent)) }

    // Header: icon + name + plan badge
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: section.iconPath
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        PlasmaComponents.Label {
            text: section.displayName
            font.bold: true
            font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.2)
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            visible: section.plan !== ""
            Layout.preferredWidth: planLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: planLabel.implicitHeight + Kirigami.Units.smallSpacing
            radius: 3
            color: Kirigami.Theme.highlightColor
            PlasmaComponents.Label {
                id: planLabel
                anchors.centerIn: parent
                text: section.plan
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.highlightedTextColor
            }
        }
    }

    // notLoggedIn state
    Rectangle {
        visible: section.st === Usage.STATE.notLoggedIn
        Layout.fillWidth: true
        Layout.preferredHeight: notLoggedCol.implicitHeight + Kirigami.Units.largeSpacing
        radius: 5
        color: Kirigami.Theme.negativeBackgroundColor

        ColumnLayout {
            id: notLoggedCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "⚠ " + section.tr("Not logged in")
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
            }
            PlasmaComponents.Label {
                text: section.tr("Run '" + section.cliName + "' to log in")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.negativeTextColor
            }
            PlasmaComponents.Button {
                text: section.tr("Open " + section.displayName)
                icon.name: "utilities-terminal"
                onClicked: section.loginRequested()
            }
        }
    }

    // tokenError state
    Rectangle {
        visible: section.st === Usage.STATE.tokenError
        Layout.fillWidth: true
        Layout.preferredHeight: tokenCol.implicitHeight + Kirigami.Units.largeSpacing
        radius: 5
        color: Kirigami.Theme.negativeBackgroundColor

        ColumnLayout {
            id: tokenCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "⚠ " + section.tr("Token expired")
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
            }
            PlasmaComponents.Button {
                text: section.tr("Open " + section.displayName)
                icon.name: "utilities-terminal"
                onClicked: section.loginRequested()
            }
        }
    }

    // rateLimited state
    Rectangle {
        visible: section.st === Usage.STATE.rateLimited
        Layout.fillWidth: true
        Layout.preferredHeight: rateCol.implicitHeight + Kirigami.Units.largeSpacing
        radius: 5
        color: Kirigami.Theme.negativeBackgroundColor

        ColumnLayout {
            id: rateCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "⚠ " + section.tr("Rate limited")
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
            }
        }
    }

    // generic error state
    Rectangle {
        visible: section.st === Usage.STATE.error
        Layout.fillWidth: true
        Layout.preferredHeight: errCol.implicitHeight + Kirigami.Units.largeSpacing
        radius: 5
        color: Kirigami.Theme.negativeBackgroundColor

        ColumnLayout {
            id: errCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "⚠ " + (section.model ? (section.model.error || section.tr("API error")) : section.tr("API error"))
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
            }
        }
    }

    // disabled state (e.g. Codex API-key mode — no usage endpoint)
    Rectangle {
        visible: section.st === Usage.STATE.disabled
        Layout.fillWidth: true
        Layout.preferredHeight: disabledCol.implicitHeight + Kirigami.Units.largeSpacing
        radius: 5
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        ColumnLayout {
            id: disabledCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: section.model && section.model.error
                    ? section.model.error
                    : section.tr("No usage endpoint for this mode")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // Windows (progress bars + reset) — shown unless hard error/notLoggedIn/disabled
    Repeater {
        model: (section.st === Usage.STATE.notLoggedIn || section.st === Usage.STATE.error || section.st === Usage.STATE.disabled)
            ? [] : section.windows

        delegate: ColumnLayout {
            id: winCol
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: section.tr(winCol.modelData.label)
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: Math.round(winCol.modelData.percent) + "%"
                    color: section.colorFor(winCol.modelData.percent)
                    font.bold: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 10
                radius: 5
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
                Rectangle {
                    width: parent.width * Math.min(winCol.modelData.percent / 100, 1)
                    height: parent.height
                    radius: 5
                    color: section.colorFor(winCol.modelData.percent)
                }
            }

            PlasmaComponents.Label {
                text: {
                    var rem = Usage.formatRemaining(winCol.modelData.resetAt)
                    var label = winCol.modelData.resetLabel || ""
                    if (label && rem) return section.tr("Resets:") + " " + label + " (" + rem + ")"
                    if (rem) return section.tr("Resets:") + " " + rem
                    return ""
                }
                visible: text !== ""
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    // Model breakdown
    PlasmaComponents.Label {
        visible: section.models.length > 0
        text: section.tr("By Model (Weekly)")
        font.bold: true
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    }

    Repeater {
        model: section.models

        delegate: RowLayout {
            id: modRow
            required property var modelData
            Layout.fillWidth: true

            PlasmaComponents.Label {
                text: section.tr(modRow.modelData.label)
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth: 60
                height: 8
                radius: 3
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
                Rectangle {
                    width: parent.width * Math.min(modRow.modelData.percent / 100, 1)
                    height: parent.height
                    radius: 3
                    color: section.colorFor(modRow.modelData.percent)
                }
            }
            PlasmaComponents.Label {
                text: Math.round(modRow.modelData.percent) + "%"
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
