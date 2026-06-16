/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Root PlasmoidItem. Instantiates one ProviderController per enabled
    provider (this Spec wires only Claude), renders compact/full via
    Repeater over the controllers' UsageModels. No provider-specific
    fetch logic lives here — it is all inside the adapter + controller.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore
import "components"
import "adapters/ClaudeAdapter.js" as ClaudeAdapter
import "adapters/CodexAdapter.js" as CodexAdapter
import "adapters/GeminiAdapter.js" as GeminiAdapter
import "adapters/GeminiEndpointAdapter.js" as GeminiEndpointAdapter
import "lib/usage.js" as Usage

PlasmoidItem {
    id: root

    Translations {
        id: i18n
        currentLanguage: Plasmoid.configuration.language || "system"
    }
    function tr(t) { return i18n.tr(t) }

    readonly property bool isVerticalLayout: Plasmoid.configuration.panelLayout === "vertical"
    property string lastUpdate: ""

    // Detected Claude Code version -> user agent (passed to adapters that want it)
    property string userAgent: ""

    // Adapter object wrapping the imported ClaudeAdapter.js namespace, so it can
    // be passed as a plain `var` to the generic controller.
    readonly property var claudeAdapter: ({
        id: ClaudeAdapter.id,
        displayName: ClaudeAdapter.displayName,
        iconName: ClaudeAdapter.iconName,
        source: ClaudeAdapter.source,
        credentialCmd: ClaudeAdapter.credentialCmd,
        rateLimitWatchCmd: ClaudeAdapter.rateLimitWatchCmd,
        parseCredential: ClaudeAdapter.parseCredential,
        buildXhr: ClaudeAdapter.buildXhr,
        parseUsage: ClaudeAdapter.parseUsage
    })

    // Adapter object wrapping the imported CodexAdapter.js namespace.
    readonly property var codexAdapter: ({
        id: CodexAdapter.id,
        displayName: CodexAdapter.displayName,
        iconName: CodexAdapter.iconName,
        source: CodexAdapter.source,
        credentialCmd: CodexAdapter.credentialCmd,
        parseCredential: CodexAdapter.parseCredential,
        buildXhr: CodexAdapter.buildXhr,
        parseUsage: CodexAdapter.parseUsage
    })

    // Adapter object wrapping the imported GeminiAdapter.js namespace (local source).
    readonly property var geminiLocalAdapter: ({
        id: GeminiAdapter.id,
        displayName: GeminiAdapter.displayName,
        iconName: GeminiAdapter.iconName,
        source: GeminiAdapter.source,
        credentialCmd: GeminiAdapter.credentialCmd,
        parseCredential: GeminiAdapter.parseCredential,
        parseUsage: GeminiAdapter.parseUsage
    })

    // Adapter object wrapping the imported GeminiEndpointAdapter.js namespace
    // (endpoint source, opt-in). Only fed to the controller when the user
    // explicitly enables geminiUseEndpoint — never by default.
    readonly property var geminiEndpointAdapter: ({
        id: GeminiEndpointAdapter.id,
        displayName: GeminiEndpointAdapter.displayName,
        iconName: GeminiEndpointAdapter.iconName,
        source: GeminiEndpointAdapter.source,
        credentialCmd: GeminiEndpointAdapter.credentialCmd,
        parseCredential: GeminiEndpointAdapter.parseCredential,
        buildXhr: GeminiEndpointAdapter.buildXhr,
        parseUsage: GeminiEndpointAdapter.parseUsage
    })

    // Absolute path to the Gemini helper, for config.scriptPath injection.
    // DataSource runs a shell, so strip the file:// prefix to a local path.
    readonly property string geminiScriptPath:
        Qt.resolvedUrl("code/gemini_count.py").toString().replace("file://", "")

    // ---- Controllers (one per enabled provider) ----
    // This Spec ships the Claude, Codex and Gemini adapters.

    ProviderController {
        id: claudeController
        adapter: root.claudeAdapter
        config: ({ refreshInterval: Plasmoid.configuration.refreshInterval || 5 })
        userAgent: root.userAgent
        onModelChanged: root._refreshLastUpdate()
    }

    ProviderController {
        id: codexController
        adapter: root.codexAdapter
        config: ({ refreshInterval: Plasmoid.configuration.refreshInterval || 5 })
        onModelChanged: root._refreshLastUpdate()
    }

    ProviderController {
        id: geminiController
        // Opt-in: when geminiUseEndpoint is true use the official endpoint adapter,
        // otherwise the default local adapter (Spec 3). Default is local.
        adapter: Plasmoid.configuration.geminiUseEndpoint
            ? root.geminiEndpointAdapter : root.geminiLocalAdapter
        config: ({
            refreshInterval: Plasmoid.configuration.refreshInterval || 5,
            scriptPath: root.geminiScriptPath,
            geminiProject: Plasmoid.configuration.geminiProject || ""
        })
        onModelChanged: root._refreshLastUpdate()
    }

    // Re-fetch immediately when the user toggles the endpoint opt-in, so the
    // adapter switch takes effect without waiting for the next interval.
    Connections {
        target: Plasmoid.configuration
        function onGeminiUseEndpointChanged() { geminiController.refresh() }
    }

    // List of active controllers (filtered by config toggles)
    readonly property var controllers: {
        var list = []
        if (Plasmoid.configuration.enableClaude !== false) list.push(claudeController)
        if (Plasmoid.configuration.enableCodex !== false) list.push(codexController)
        if (Plasmoid.configuration.enableGemini !== false) list.push(geminiController)
        return list
    }

    // Controllers shown on the panel: drop providers that are notLoggedIn or
    // disabled (those live only in the popup). ok/loading/rateLimited/
    // tokenError/error still appear. Recomputed whenever any model.state moves.
    readonly property var panelControllers: {
        var list = []
        for (var i = 0; i < controllers.length; i++) {
            var m = controllers[i].model
            var s = m ? m.state : Usage.STATE.loading
            if (s === Usage.STATE.notLoggedIn || s === Usage.STATE.disabled) continue
            list.push(controllers[i])
        }
        return list
    }

    readonly property bool anyData: {
        for (var i = 0; i < controllers.length; i++) {
            var m = controllers[i].model
            if (m && (m.state === Usage.STATE.ok
                || m.state === Usage.STATE.rateLimited
                || m.state === Usage.STATE.tokenError)) return true
        }
        return false
    }

    function iconPathFor(controller) {
        var name = (controller && controller.adapter) ? controller.adapter.iconName : "widget.svg"
        return Qt.resolvedUrl("../icons/" + name)
    }

    function _refreshLastUpdate() {
        // newest lastSuccess among controllers
        var newest = 0
        for (var i = 0; i < controllers.length; i++) {
            var m = controllers[i].model
            if (m && m.lastSuccess > newest) newest = m.lastSuccess
        }
        if (newest > 0) {
            root.lastUpdate = Qt.formatTime(new Date(newest), "hh:mm:ss")
        }
    }

    function refreshAll() {
        for (var i = 0; i < controllers.length; i++) controllers[i].refresh()
    }

    // ---- Claude Code version detection (shared user agent) ----
    Plasma5Support.DataSource {
        id: versionReader
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            var match = stdout.match(/^(\d+\.\d+\.\d+)/)
            if (match) root.userAgent = "claude-code/" + match[1]
        }
    }

    // ---- launcher for "Open Claude" actions ----
    Plasma5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }
    function launchClaude() {
        launcher.connectSource("bash -c 'cd $HOME && if command -v konsole >/dev/null; then konsole --hold -e env -u CLAUDECODE bash -lc claude; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- env -u CLAUDECODE bash -lc \"claude; exec bash\"; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e \"env -u CLAUDECODE bash -lc claude\"; elif command -v xterm >/dev/null; then xterm -hold -e env -u CLAUDECODE bash -lc claude; fi &'")
    }
    function launchCodex() {
        launcher.connectSource("bash -c 'cd $HOME && if command -v konsole >/dev/null; then konsole --hold -e bash -lc codex; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- bash -lc \"codex; exec bash\"; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e \"bash -lc codex\"; elif command -v xterm >/dev/null; then xterm -hold -e bash -lc codex; fi &'")
    }
    function launchGemini() {
        launcher.connectSource("bash -c 'cd $HOME && if command -v konsole >/dev/null; then konsole --hold -e bash -lc gemini; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- bash -lc \"gemini; exec bash\"; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e \"bash -lc gemini\"; elif command -v xterm >/dev/null; then xterm -hold -e bash -lc gemini; fi &'")
    }
    // Dispatch the popup "login" action to the right launcher by provider id.
    function launchProvider(providerId) {
        if (providerId === "codex") root.launchCodex()
        else if (providerId === "gemini") root.launchGemini()
        else root.launchClaude()
    }

    // ============ COMPACT ============
    compactRepresentation: Item {
        Layout.minimumWidth: usageFlow.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.minimumHeight: root.isVerticalLayout
            ? usageFlow.implicitHeight + Kirigami.Units.largeSpacing * 2
            : Kirigami.Units.iconSizes.medium
        Layout.preferredWidth: usageFlow.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredHeight: root.isVerticalLayout
            ? usageFlow.implicitHeight + Kirigami.Units.largeSpacing * 2 : -1

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        GridLayout {
            id: usageFlow
            anchors.centerIn: parent
            columns: root.isVerticalLayout ? 1 : -1
            rows: root.isVerticalLayout ? -1 : 1
            flow: root.isVerticalLayout ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            // Empty-state placeholder: no provider is in use on the panel
            // (none enabled, or all notLoggedIn/disabled) — show a single
            // widget icon instead of per-provider error dots.
            Kirigami.Icon {
                visible: root.panelControllers.length === 0
                source: Qt.resolvedUrl("../icons/widget.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                opacity: 0.6
            }

            Repeater {
                model: root.panelControllers

                // Wrap each provider with a leading thin separator (skipped for
                // the first): vertical layout uses a horizontal line, horizontal
                // layout uses a vertical line.
                delegate: GridLayout {
                    id: panelCell
                    required property var modelData
                    required property int index
                    columns: root.isVerticalLayout ? 1 : -1
                    rows: root.isVerticalLayout ? -1 : 1
                    flow: root.isVerticalLayout ? GridLayout.TopToBottom : GridLayout.LeftToRight
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    // Vertical layout -> horizontal divider above; horizontal
                    // layout -> vertical divider to the left.
                    Rectangle {
                        visible: panelCell.index > 0
                        Layout.preferredWidth: root.isVerticalLayout ? Kirigami.Units.gridUnit : 1
                        Layout.preferredHeight: root.isVerticalLayout ? 1 : Kirigami.Units.iconSizes.small
                        color: Kirigami.Theme.disabledTextColor
                        opacity: 0.3
                    }

                    ProviderPanelItem {
                        model: panelCell.modelData.model
                        panelStyle: Plasmoid.configuration.panelStyle || "text"
                        showIcon: Plasmoid.configuration.showIcon !== false
                        vertical: root.isVerticalLayout
                        iconPath: root.iconPathFor(panelCell.modelData)
                    }
                }
            }
        }
    }

    // ============ FULL ============
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 18

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing

            // Title
            PlasmaComponents.Label {
                text: root.tr("Agent Usage")
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.3)
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.3
            }

            // Placeholder when no provider enabled
            PlasmaComponents.Label {
                visible: root.controllers.length === 0
                text: root.tr("Enable a provider in settings")
                color: Kirigami.Theme.disabledTextColor
                font.italic: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.controllers

                delegate: ColumnLayout {
                    id: popupCell
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.mediumSpacing

                    ProviderPopupSection {
                        Layout.fillWidth: true
                        model: popupCell.modelData.model
                        iconPath: root.iconPathFor(popupCell.modelData)
                        trFn: root.tr
                        onLoginRequested: root.launchProvider(popupCell.modelData.model ? popupCell.modelData.model.id : "claude")
                    }

                    // Separator between provider sections (not after the last)
                    Kirigami.Separator {
                        visible: popupCell.index < root.controllers.length - 1
                        Layout.fillWidth: true
                    }
                }
            }

            // Rate limit warning (low refresh)
            PlasmaComponents.Label {
                visible: (Plasmoid.configuration.refreshInterval || 5) < 5
                text: "⚠ " + root.tr("Values under 5 min may cause rate limiting")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.neutralTextColor
                font.italic: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.3
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: root.lastUpdate !== ""
                        ? root.tr("Updated:") + " " + root.lastUpdate
                        : root.tr("Loading...")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Button {
                    icon.name: "view-refresh"
                    text: root.tr("Refresh")
                    onClicked: root.refreshAll()
                }
            }
        }
    }

    // ---- background / panel ----
    readonly property bool isOnPanel: Plasmoid.location === PlasmaCore.Types.TopEdge
        || Plasmoid.location === PlasmaCore.Types.BottomEdge
        || Plasmoid.location === PlasmaCore.Types.LeftEdge
        || Plasmoid.location === PlasmaCore.Types.RightEdge

    Plasmoid.backgroundHints: isOnPanel ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground

    Rectangle {
        visible: !root.isOnPanel
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: Plasmoid.configuration.backgroundOpacity
        radius: Kirigami.Units.cornerRadius
    }

    // ---- icon install (for about page) ----
    Plasma5Support.DataSource {
        id: iconInstaller
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    Plasmoid.icon: "agent-usage-widget"
    toolTipMainText: root.tr("Agent Usage")
    toolTipSubText: {
        var parts = []
        for (var i = 0; i < root.panelControllers.length; i++) {
            var m = root.panelControllers[i].model
            if (!m || !m.windows || m.windows.length === 0) continue
            var name = m.displayName || m.id
            parts.push(name + " " + Math.round(m.windows[0].percent) + "%")
        }
        return parts.length > 0 ? parts.join(" · ") : root.tr("No usage data")
    }

    Component.onCompleted: {
        var iconSource = Qt.resolvedUrl("../icons/widget.svg").toString().replace("file://", "")
        iconInstaller.connectSource("bash -c 'ICON_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps && mkdir -p $ICON_DIR && cp \"" + iconSource + "\" $ICON_DIR/agent-usage-widget.svg && chmod 644 $ICON_DIR/agent-usage-widget.svg 2>/dev/null'")
        versionReader.connectSource("claude --version 2>/dev/null")
    }
}
