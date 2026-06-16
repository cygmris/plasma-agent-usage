.import "../lib/usage.js" as Usage
/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Gemini provider adapter — pure data logic, no side effects.
    Importable from Node (unit tests) and from QML.

    source = "local": there is no HTTP endpoint. The ProviderController runs
    `credentialCmd` (which invokes the python3 helper), feeds its stdout to
    `parseCredential`, and — when ok — re-feeds the SAME stdout to
    `parseUsage(200, stdout, ...)`. So both functions parse the helper's JSON
    contract:
      { ok, account, tier, tierLabel, dailyLimit,
        requestsToday, requestsTotal, resetAt }

    Contract (mirrors ClaudeAdapter.js / CodexAdapter.js):
      id, displayName, iconName, source
      credentialCmd(config) -> shell string
      parseCredential(stdout, config) -> { ok, plan, account, ... }
      parseUsage(httpStatus, responseText, getHeader, credState) -> UsageModel
*/

var id = "gemini";
var displayName = "Gemini";
var iconName = "gemini.svg";
var source = "local";

// Shell that runs the helper. The controller passes the resolved absolute path
// via config.scriptPath (injected by main.qml). No scriptPath -> no command,
// which the controller treats as notLoggedIn.
function credentialCmd(config) {
    var path = (config && config.scriptPath) ? config.scriptPath : "";
    if (!path) return "";
    return "python3 '" + path + "' 2>/dev/null";
}

// stdout (helper JSON) -> credential state
function parseCredential(stdout, config) {
    var text = (stdout || "").trim();
    if (text.length <= 2) {
        return { ok: false, state: Usage.STATE.notLoggedIn, account: "", plan: "" };
    }
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return { ok: false, state: Usage.STATE.notLoggedIn, account: "", plan: "", error: "parse" };
    }
    if (!data || data.ok === false) {
        return { ok: false, state: Usage.STATE.notLoggedIn, account: "", plan: "" };
    }
    return {
        ok: true,
        account: data.account || "",
        plan: data.tierLabel || ""
    };
}

// httpStatus + body + header-getter + credState -> UsageModel
// For local source the controller always calls this with status 200 and the
// helper stdout as `responseText`.
function parseUsage(httpStatus, responseText, getHeader, credState) {
    var plan = (credState && credState.plan) ? credState.plan : "";
    var base = { displayName: displayName, plan: plan, source: source };

    var text = (responseText || "").trim();
    if (text.length <= 2) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.notLoggedIn
        }));
    }

    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "Parse error"
        }));
    }

    if (!data || data.ok === false) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.notLoggedIn
        }));
    }

    var limit = Number(data.dailyLimit) || 0;
    var used = Number(data.requestsToday) || 0;
    var percent = limit > 0 ? (used / limit) * 100 : 0;

    var windows = [
        Usage.makeWindow("daily", "Daily (requests)", percent, data.resetAt || null)
    ];

    return Usage.makeModel(id, Object.assign({}, base, {
        state: Usage.STATE.ok,
        plan: data.tierLabel || plan,
        windows: windows,
        models: [],
        lastSuccess: Date.now()
    }));
}
