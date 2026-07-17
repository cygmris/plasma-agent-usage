.import "../lib/usage.js" as Usage
/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Claude provider adapter — pure data logic, no side effects.
    Importable from Node (unit tests) and from QML.

    Contract (see design.md):
      id, displayName, iconName, source
      credentialCmd(config) -> shell string
      parseCredential(stdout, config) -> { ok, plan, accessToken, ... }
      buildXhr(credState, config) -> { url, method, headers, body } | null
      parseUsage(httpStatus, responseText, getHeader, credState) -> UsageModel
      rateLimitWatchCmd(config) -> shell string   (optional hook)
*/

var id = "claude";
var displayName = "Claude";
var iconName = "claude.svg";
var source = "endpoint";

var PLAN_MAP = {
    "default_claude_pro": "Pro",
    "default_claude_max_5x": "Max 5x",
    "default_claude_max_20x": "Max 20x"
};

// Default user agent (controller may override with detected `claude --version`)
function defaultUserAgent(nowDate) {
    var d = nowDate || new Date();
    // yyyy.M.d (no zero-padding), mirrors baseline
    return "claude-code/" + d.getFullYear() + "." + (d.getMonth() + 1) + "." + d.getDate();
}

// Shell to read the OAuth credentials file
function credentialCmd(config) {
    return "cat $HOME/.claude/.credentials.json 2>/dev/null";
}

// Token watcher: poll credentials during rate limit to detect a refreshed token
function rateLimitWatchCmd(config) {
    return "cat $HOME/.claude/.credentials.json 2>/dev/null";
}

// stdout (credentials json) -> credential state
function parseCredential(stdout, config) {
    var text = (stdout || "").trim();
    if (text.length <= 10) {
        return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: "" };
    }
    try {
        var creds = JSON.parse(text);
        var oauth = creds.claudeAiOauth || {};
        var token = oauth.accessToken || "";
        var tier = oauth.rateLimitTier || "default_claude_pro";
        var plan = PLAN_MAP[tier] || tier;
        if (!token) {
            return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: plan };
        }
        return { ok: true, accessToken: token, plan: plan, tier: tier };
    } catch (e) {
        return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: "", error: "parse" };
    }
}

// credState -> XHR descriptor
function buildXhr(credState, config) {
    if (!credState || !credState.accessToken) return null;
    var ua = (config && config.userAgent) ? config.userAgent : defaultUserAgent();
    return {
        url: "https://api.anthropic.com/api/oauth/usage",
        method: "GET",
        headers: {
            "Content-Type": "application/json",
            "User-Agent": ua,
            "anthropic-beta": "oauth-2025-04-20",
            "Authorization": "Bearer " + credState.accessToken
        },
        body: null
    };
}

// httpStatus + body + header-getter + credState -> UsageModel
function parseUsage(httpStatus, responseText, getHeader, credState) {
    var plan = (credState && credState.plan) ? credState.plan : "";
    var base = { displayName: displayName, plan: plan, source: source };

    if (httpStatus === 401) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.tokenError, error: "Token expired"
        }));
    }

    if (httpStatus === 429) {
        var retryAfter = 0;
        if (typeof getHeader === "function") {
            retryAfter = parseInt(getHeader("retry-after") || "0", 10) || 0;
        }
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.rateLimited, error: "Rate limited", retryAfter: retryAfter
        }));
    }

    if (httpStatus !== 200) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "API error (" + httpStatus + ")"
        }));
    }

    var data;
    try {
        data = JSON.parse(responseText);
    } catch (e) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "Parse error"
        }));
    }

    var fiveHour = data.five_hour || {};
    var sevenDay = data.seven_day || {};

    var windows = [
        Usage.makeWindow("session", "Session (5hr)", fiveHour.utilization || 0, fiveHour.resets_at || null),
        Usage.makeWindow("weekly", "Weekly (7day)", sevenDay.utilization || 0, sevenDay.resets_at || null)
    ];

    var models = [];
    // 2026+ schema: per-model weekly usage lives in limits[] as scoped entries
    // (kind "weekly_scoped") carrying scope.model.display_name. The legacy
    // seven_day_<model> top-level keys are now null on these accounts.
    var limits = Array.isArray(data.limits) ? data.limits : [];
    for (var i = 0; i < limits.length; i++) {
        var lim = limits[i] || {};
        var model = (lim.scope && lim.scope.model) || null;
        var name = model && model.display_name;
        if (name) {
            models.push(Usage.makeModelUsage(name, lim.percent || 0));
        }
    }
    // Backward-compat fallback: older API exposed seven_day_sonnet/opus directly.
    if (models.length === 0) {
        if (data.seven_day_sonnet) {
            models.push(Usage.makeModelUsage("Sonnet", data.seven_day_sonnet.utilization || 0));
        }
        if (data.seven_day_opus) {
            models.push(Usage.makeModelUsage("Opus", data.seven_day_opus.utilization || 0));
        }
    }

    return Usage.makeModel(id, Object.assign({}, base, {
        state: Usage.STATE.ok,
        windows: windows,
        models: models,
        lastSuccess: Date.now()
    }));
}
