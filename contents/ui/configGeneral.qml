/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    property string cfg_language
    property int cfg_refreshInterval
    property bool cfg_enableClaude
    property bool cfg_enableCodex
    property bool cfg_enableGemini
    property bool cfg_geminiUseEndpoint
    property string cfg_geminiProject
    property string cfg_panelLayout
    property bool cfg_showIcon
    property string cfg_panelStyle
    property double cfg_backgroundOpacity

    Translations {
        id: trans
        currentLanguage: cfg_language || "system"
    }

    function tr(text) { return trans.tr(text); }

    readonly property var languageValues: [
        "system", "en_US", "hu_HU", "de_DE", "fr_FR", "es_ES",
        "it_IT", "pt_BR", "ru_RU", "pl_PL", "nl_NL", "tr_TR",
        "ja_JP", "ko_KR", "zh_CN", "zh_TW"
    ]

    readonly property var languageNames: [
        tr("System default"), "English", "Magyar", "Deutsch",
        "Français", "Español", "Italiano", "Português (Brasil)",
        "Русский", "Polski", "Nederlands", "Türkçe",
        "日本語", "한국어", "简体中文", "繁體中文"
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: languageCombo
            Kirigami.FormData.label: tr("Language:")
            model: languageNames
            currentIndex: languageValues.indexOf(cfg_language)
            onActivated: index => { cfg_language = languageValues[index] }
        }

        RowLayout {
            Kirigami.FormData.label: tr("Refresh interval:")
            QQC2.SpinBox {
                id: refreshSpinBox
                from: 1
                to: 999
                stepSize: 1
                value: cfg_refreshInterval
                onValueChanged: { cfg_refreshInterval = value }
            }
            QQC2.Label { text: tr("minutes") }
        }

        QQC2.Label {
            visible: cfg_refreshInterval < 5
            text: "⚠ " + tr("Values under 5 min may cause rate limiting")
            color: Kirigami.Theme.negativeTextColor
            font.italic: true
            Layout.fillWidth: true
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: tr("Providers")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: tr("Enable:")
            text: tr("Claude")
            checked: cfg_enableClaude
            onCheckedChanged: cfg_enableClaude = checked
        }
        QQC2.CheckBox {
            text: tr("Codex")
            checked: cfg_enableCodex
            onCheckedChanged: cfg_enableCodex = checked
        }
        QQC2.CheckBox {
            text: tr("Gemini")
            checked: cfg_enableGemini
            onCheckedChanged: cfg_enableGemini = checked
        }

        QQC2.CheckBox {
            id: geminiEndpointCheck
            Kirigami.FormData.label: tr("Gemini quota:")
            text: tr("Use official Gemini quota endpoint")
            checked: cfg_geminiUseEndpoint
            onCheckedChanged: cfg_geminiUseEndpoint = checked
        }

        QQC2.Label {
            visible: geminiEndpointCheck.checked
            text: "⚠ " + tr("Uses Google's official endpoint for exact quota, but Google forbids third-party tools from calling it with CLI credentials — this risks account suspension. Use at your own risk.")
            color: Kirigami.Theme.negativeTextColor
            font.bold: true
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
        }

        QQC2.TextField {
            Kirigami.FormData.label: tr("Gemini project (optional):")
            visible: geminiEndpointCheck.checked
            text: cfg_geminiProject
            onTextChanged: cfg_geminiProject = text
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: tr("Panel display")
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: tr("Layout:")
            model: [tr("Horizontal"), tr("Vertical")]
            currentIndex: cfg_panelLayout === "vertical" ? 1 : 0
            onCurrentIndexChanged: cfg_panelLayout = currentIndex === 1 ? "vertical" : "horizontal"
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: tr("Icon:")
            text: tr("Show Claude icon")
            checked: cfg_showIcon
            onCheckedChanged: cfg_showIcon = checked
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: tr("Style:")
            model: [tr("Text"), tr("Circular"), tr("Bar")]
            currentIndex: cfg_panelStyle === "circular" ? 1 : cfg_panelStyle === "bar" ? 2 : 0
            onCurrentIndexChanged: {
                var styles = ["text", "circular", "bar"]
                cfg_panelStyle = styles[currentIndex]
            }
        }

        RowLayout {
            Kirigami.FormData.label: tr("Background opacity (desktop):")
            QQC2.Slider {
                id: opacitySlider
                from: 0.0
                to: 1.0
                stepSize: 0.05
                value: cfg_backgroundOpacity
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                onMoved: { cfg_backgroundOpacity = value }
            }
            QQC2.Label {
                text: Math.round(opacitySlider.value * 100) + "%"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
            }
        }
    }
}
