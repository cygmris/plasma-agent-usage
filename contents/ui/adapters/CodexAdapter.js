.import "../lib/usage.js" as Usage
/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Codex provider adapter — pure data logic, no side effects.
    Importable from Node (unit tests) and from QML.

    Contract (see design.md, mirrors ClaudeAdapter.js):
      id, displayName, iconName, source
      credentialCmd(config) -> shell string
      parseCredential(stdout, config) -> { ok, plan, accessToken, accountId, ... }
      buildXhr(credState, config) -> { url, method, headers, body } | null
      parseUsage(httpStatus, responseText, getHeader, credState) -> UsageModel

    Key difference vs Claude: Codex `reset_at` is an *epoch second*, not an
    ISO string — converted with `new Date(reset_at * 1000).toISOString()`.
*/

var id = "codex";
var displayName = "Codex";
var iconName = "codex.svg";
var source = "endpoint";

var PLAN_MAP = {
    "pro": "Pro",
    "plus": "Plus",
    "team": "Team",
    "business": "Business",
    "enterprise": "Enterprise",
    "free": "Free"
};

function mapPlan(planType) {
    if (!planType) return "";
    if (PLAN_MAP[planType]) return PLAN_MAP[planType];
    // Fallback: capitalize first letter
    return planType.charAt(0).toUpperCase() + planType.slice(1);
}

// limit_window_seconds -> human label (with hour/day fallback)
function labelFor(sec) {
    if (sec === 18000) return "Session (5h)";
    if (sec === 604800) return "Weekly (7d)";
    var n = Number(sec);
    if (isNaN(n) || n <= 0) return "";
    if (n % 86400 === 0) return Math.round(n / 86400) + "d";
    return Math.round(n / 3600) + "h";
}

// epoch seconds -> ISO string (null/invalid safe)
function isoFromEpochSec(s) {
    var n = Number(s);
    if (isNaN(n) || n <= 0) return null;
    return new Date(n * 1000).toISOString();
}

// Shell to read the Codex auth file
function credentialCmd(config) {
    return "cat $HOME/.codex/auth.json 2>/dev/null";
}

// stdout (auth.json) -> credential state
function parseCredential(stdout, config) {
    var text = (stdout || "").trim();
    if (text.length <= 2) {
        return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: "" };
    }
    var creds;
    try {
        creds = JSON.parse(text);
    } catch (e) {
        return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: "", error: "parse" };
    }

    var authMode = creds.auth_mode || "";
    if (authMode !== "chatgpt") {
        return {
            ok: false,
            state: Usage.STATE.disabled,
            accessToken: "",
            plan: "",
            note: "Codex API-key mode has no usage endpoint"
        };
    }

    var tokens = creds.tokens || {};
    var token = tokens.access_token || "";
    var accountId = tokens.account_id || "";
    if (!token) {
        return { ok: false, state: Usage.STATE.notLoggedIn, accessToken: "", plan: "" };
    }
    return { ok: true, accessToken: token, accountId: accountId, plan: "" };
}

// credState -> XHR descriptor
function buildXhr(credState, config) {
    if (!credState || !credState.accessToken) return null;
    return {
        url: "https://chatgpt.com/backend-api/wham/usage",
        method: "GET",
        headers: {
            "Authorization": "Bearer " + credState.accessToken,
            "ChatGPT-Account-Id": credState.accountId || "",
            "User-Agent": "codex-cli",
            "Accept": "application/json"
        },
        body: null
    };
}

// build a window from a raw window object; returns null if missing
function windowFrom(key, raw) {
    if (!raw || typeof raw !== "object") return null;
    return Usage.makeWindow(
        key,
        labelFor(raw.limit_window_seconds),
        raw.used_percent || 0,
        isoFromEpochSec(raw.reset_at)
    );
}

// httpStatus + body + header-getter + credState -> UsageModel
function parseUsage(httpStatus, responseText, getHeader, credState) {
    var base = { displayName: displayName, plan: "", source: source };

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

    var rateLimit = data.rate_limit;
    if (!rateLimit || typeof rateLimit !== "object") {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "No rate limit data"
        }));
    }

    var windows = [];
    var primary = windowFrom("primary", rateLimit.primary_window);
    if (primary) windows.push(primary);
    var secondary = windowFrom("secondary", rateLimit.secondary_window);
    if (secondary) windows.push(secondary);

    if (windows.length === 0) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "No usage windows"
        }));
    }

    return Usage.makeModel(id, Object.assign({}, base, {
        state: Usage.STATE.ok,
        plan: mapPlan(data.plan_type),
        windows: windows,
        models: [],
        lastSuccess: Date.now()
    }));
}
