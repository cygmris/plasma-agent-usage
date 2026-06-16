/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Generic per-provider runtime. One instance per enabled provider.
    Holds an adapter (pure JS) and runs the full pipeline:
      read credentials (DataSource) -> parseCredential
        -> (endpoint) buildXhr + XMLHttpRequest -> parseUsage
        -> produce read-only `model` (UsageModel)
    Manages: 55s min fetch interval, refreshInterval timer, 24h cache,
    stale flag, 401/429 states, and (if adapter exposes rateLimitWatchCmd)
    rate-limit token-watch self-healing.

    NO provider-specific fetch logic lives here — everything goes through
    the adapter contract.
*/

import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "lib/usage.js" as Usage

Item {
    id: controller

    // The adapter (pure JS module object: id, displayName, credentialCmd, ...)
    property var adapter
    // Plasmoid.configuration (or a subset). refreshInterval in minutes, plus userAgent.
    property var config: ({})
    // Detected user agent passed down (e.g. claude-code/<ver>); adapter may use it.
    property string userAgent: ""

    // Read-only UsageModel produced by this controller.
    readonly property alias model: d.model

    readonly property int minFetchIntervalMs: 55000
    readonly property string cachePath: "$HOME/.local/share/plasma-agent-usage-cache.json"

    QtObject {
        id: d
        property var model: controller.adapter
            ? Usage.makeModel(controller.adapter.id, {
                  displayName: controller.adapter.displayName,
                  source: controller.adapter.source,
                  state: Usage.STATE.loading
              })
            : Usage.makeModel("unknown", { state: Usage.STATE.loading })

        property var credState: null
        property double lastFetchTime: 0
        property double lastSuccessTime: 0
        property int rateLimitRetryCount: 0
        property int rateLimitRetryMs: 0   // from retry-after
    }

    // ---- stale threshold ----
    readonly property int refreshMinutes: Math.max((controller.config && controller.config.refreshInterval) || 5, 1)
    readonly property int staleThresholdMs:
        (d.model && d.model.state === Usage.STATE.rateLimited && d.rateLimitRetryMs > 0)
            ? d.rateLimitRetryMs + 60000
            : refreshMinutes * 60000 * 3

    // Patch a few fields onto the current model and reassign (so bindings update)
    function _patchModel(patch) {
        var m = d.model || {}
        var copy = {}
        for (var k in m) { if (m.hasOwnProperty(k)) copy[k] = m[k] }
        for (var j in patch) { if (patch.hasOwnProperty(j)) copy[j] = patch[j] }
        d.model = copy
    }

    // ---------- DataSources ----------

    // Reads credentials / local data
    Plasma5Support.DataSource {
        id: credReader
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || ""
            disconnectSource(sourceName)
            controller._onCredentials(stdout)
        }
    }

    // Token watcher (rate-limit self-heal); only used if adapter provides the hook
    Plasma5Support.DataSource {
        id: tokenWatcher
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || ""
            disconnectSource(sourceName)
            controller._onTokenWatch(stdout)
        }
    }

    // Cache writer
    Plasma5Support.DataSource {
        id: cacheWriter
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    // Cache reader (startup)
    Plasma5Support.DataSource {
        id: cacheReader
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            controller._onCacheLoaded(stdout)
        }
    }

    // ---------- pipeline ----------

    function refresh() {
        if (!controller.adapter) return
        var cmd = controller.adapter.credentialCmd(controller._adapterConfig())
        if (!cmd) {
            // local provider with no credential step: go straight to (no-op) usage
            controller._onCredentials("")
            return
        }
        credReader.connectSource(cmd)
    }

    function _adapterConfig() {
        var c = {}
        if (controller.config) {
            for (var k in controller.config) {
                if (controller.config.hasOwnProperty(k)) c[k] = controller.config[k]
            }
        }
        if (controller.userAgent) c.userAgent = controller.userAgent
        return c
    }

    function _onCredentials(stdout) {
        var cred = controller.adapter.parseCredential(stdout, controller._adapterConfig())
        d.credState = cred

        if (!cred || cred.ok === false) {
            controller._patchModel({
                state: cred && cred.state ? cred.state : Usage.STATE.notLoggedIn,
                plan: cred && cred.plan ? cred.plan : (d.model ? d.model.plan : "")
            })
            return
        }

        // plan available early
        if (cred.plan) controller._patchModel({ plan: cred.plan })

        if (controller.adapter.source === "endpoint") {
            controller._fetchUsage(false)
        } else {
            // local source: adapter.parseUsage with no http
            var m = controller.adapter.parseUsage(200, stdout, function() { return null }, cred)
            controller._applyModel(m)
        }
    }

    function _fetchUsage(force) {
        var now = Date.now()
        if (!force && d.lastFetchTime > 0 && (now - d.lastFetchTime) < controller.minFetchIntervalMs) {
            return
        }
        d.lastFetchTime = now

        var req = controller.adapter.buildXhr(d.credState, controller._adapterConfig())
        if (!req) {
            controller._patchModel({ state: Usage.STATE.notLoggedIn })
            return
        }

        var xhr = new XMLHttpRequest()
        xhr.open(req.method || "GET", req.url)
        if (req.headers) {
            for (var h in req.headers) {
                if (req.headers.hasOwnProperty(h)) xhr.setRequestHeader(h, req.headers[h])
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var getHeader = function(name) { return xhr.getResponseHeader(name) }
            var m = controller.adapter.parseUsage(xhr.status, xhr.responseText, getHeader, d.credState)
            controller._applyModel(m)
        }
        xhr.send(req.body || null)
    }

    function _applyModel(m) {
        if (!m) return

        if (m.state === Usage.STATE.ok) {
            d.lastSuccessTime = Date.now()
            d.rateLimitRetryCount = 0
            d.rateLimitRetryMs = 0
            m.lastSuccess = d.lastSuccessTime
            m.isStale = false
            d.model = m
            controller._saveCache(m)
        } else if (m.state === Usage.STATE.rateLimited) {
            d.rateLimitRetryCount++
            if (m.retryAfter && m.retryAfter > 0) d.rateLimitRetryMs = m.retryAfter * 1000
            d.lastFetchTime = 0  // allow retry timer to fire
            // keep previous windows/models so the panel can still show dimmed values
            controller._patchModel({ state: Usage.STATE.rateLimited, error: m.error || "" })
        } else if (m.state === Usage.STATE.tokenError) {
            controller._patchModel({ state: Usage.STATE.tokenError, error: m.error || "" })
        } else {
            // error / other: keep cached values if any, just flip state
            controller._patchModel({ state: m.state, error: m.error || "" })
        }
    }

    // ---------- cache ----------

    function _saveCache(m) {
        var record = {
            id: m.id,
            displayName: m.displayName,
            plan: m.plan,
            state: m.state,
            source: m.source,
            windows: m.windows,
            models: m.models,
            timestamp: Date.now()
        }
        // Merge into the multi-provider cache file under this provider's id.
        // We keep an in-memory mirror of the whole file (seeded by cacheReader at
        // startup) and rewrite the merged object — dependency-free, no jq/python.
        var pid = m.id
        controller._cacheMemory[pid] = record
        var full = JSON.stringify(controller._cacheMemory).replace(/'/g, "'\\''")
        cacheWriter.connectSource("mkdir -p $(dirname " + controller.cachePath + ") && printf '%s' '" + full + "' > " + controller.cachePath)
    }

    // In-memory mirror of the whole cache file (per-provider keyed)
    property var _cacheMemory: ({})

    function _onCacheLoaded(stdout) {
        if (stdout.length <= 2) return
        try {
            var all = JSON.parse(stdout)
            controller._cacheMemory = all || {}
            var pid = controller.adapter ? controller.adapter.id : ""
            var rec = all[pid]
            if (!rec) return
            var age = Date.now() - (rec.timestamp || 0)
            if (age >= 86400000) return  // > 24h, ignore
            // Only seed if we don't already have fresh data
            if (d.lastSuccessTime > 0) return
            d.lastSuccessTime = rec.timestamp || 0
            controller._patchModel({
                plan: rec.plan || "",
                windows: rec.windows || [],
                models: rec.models || [],
                state: d.model.state === Usage.STATE.loading ? Usage.STATE.ok : d.model.state,
                lastSuccess: rec.timestamp || 0,
                isStale: age > controller.staleThresholdMs
            })
        } catch (e) {
            // ignore cache parse errors
        }
    }

    function loadCache() {
        cacheReader.connectSource("cat " + controller.cachePath + " 2>/dev/null")
    }

    // ---------- timers ----------

    Timer {
        id: staleTimer
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            if (d.lastSuccessTime > 0) {
                var stale = (Date.now() - d.lastSuccessTime) > controller.staleThresholdMs
                if (d.model && d.model.isStale !== stale) {
                    controller._patchModel({ isStale: stale })
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: controller.refreshMinutes * 60000
        running: d.model ? d.model.state !== Usage.STATE.rateLimited : true
        repeat: true
        onTriggered: controller.refresh()
    }

    // Rate-limit backoff: retry-after + 10s buffer, else 5/10/15min capped
    readonly property int rateLimitBackoffMs: d.rateLimitRetryMs > 0
        ? d.rateLimitRetryMs + 10000
        : Math.min((d.rateLimitRetryCount + 1) * 300000, 900000)

    Timer {
        id: rateLimitRetryTimer
        interval: controller.rateLimitBackoffMs
        running: d.model ? d.model.state === Usage.STATE.rateLimited : false
        repeat: true
        onTriggered: controller.refresh()
    }

    // Token watcher during rate limit (only if adapter exposes the hook)
    Timer {
        id: tokenWatchTimer
        interval: 30000
        running: (d.model ? d.model.state === Usage.STATE.rateLimited : false)
            && controller.adapter && typeof controller.adapter.rateLimitWatchCmd === "function"
        repeat: true
        onTriggered: {
            var cmd = controller.adapter.rateLimitWatchCmd(controller._adapterConfig())
            if (cmd) tokenWatcher.connectSource(cmd)
        }
    }

    function _onTokenWatch(stdout) {
        var cred = controller.adapter.parseCredential(stdout, controller._adapterConfig())
        if (cred && cred.ok && cred.accessToken
                && (!d.credState || cred.accessToken !== d.credState.accessToken)) {
            d.credState = cred
            d.rateLimitRetryCount = 0
            d.rateLimitRetryMs = 0
            d.lastFetchTime = 0
            controller._patchModel({ state: Usage.STATE.loading })
            controller._fetchUsage(true)
        }
    }

    Component.onCompleted: {
        if (controller.adapter) {
            controller.loadCache()
            controller.refresh()
        }
    }
}
