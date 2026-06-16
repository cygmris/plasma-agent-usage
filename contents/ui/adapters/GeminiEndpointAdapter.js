.import "../lib/usage.js" as Usage
/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Gemini *endpoint* provider adapter — pure data logic, no side effects.
    Importable from Node (unit tests) and from QML.

    OPT-IN ONLY. This adapter targets Google's official
    `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` endpoint using the
    gemini-cli OAuth credential. Google forbids third-party tools from calling it
    with CLI credentials — using it carries a real risk of account suspension. It
    must NEVER be enabled by default; the controller only ever instantiates this
    adapter when the user explicitly opts in via `geminiUseEndpoint`.

    Best-effort, NOT live-verified: the 200 response shape below was reconstructed
    from research, not exercised against the real endpoint (ToS-grey). See
    design.md §Data Models.

    Contract (mirrors CodexAdapter.js):
      id, displayName, iconName, source
      credentialCmd(config) -> shell string
      parseCredential(stdout, config) -> { ok, token, expiry, state? }
      buildXhr(credState, config) -> { url, method, headers, body } | null
      parseUsage(httpStatus, responseText, getHeader, credState) -> UsageModel
*/

var id = "gemini";
var displayName = "Gemini";
var iconName = "gemini.svg";
var source = "endpoint";

var ENDPOINT = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota";

// Shell to read the gemini-cli OAuth credential file.
function credentialCmd(config) {
    return "cat $HOME/.gemini/oauth_creds.json 2>/dev/null";
}

// stdout (oauth_creds.json) -> credential state.
// Takes access_token + expiry_date (epoch ms); expired -> tokenError.
function parseCredential(stdout, config) {
    var text = (stdout || "").trim();
    if (text.length <= 2) {
        return { ok: false, state: Usage.STATE.notLoggedIn, token: "" };
    }
    var creds;
    try {
        creds = JSON.parse(text);
    } catch (e) {
        return { ok: false, state: Usage.STATE.notLoggedIn, token: "", error: "parse" };
    }

    var token = creds.access_token || "";
    if (!token) {
        return { ok: false, state: Usage.STATE.notLoggedIn, token: "" };
    }

    var expiry = Number(creds.expiry_date) || 0;
    if (expiry > 0 && Date.now() > expiry) {
        return { ok: false, state: Usage.STATE.tokenError, token: "", expiry: expiry };
    }

    return { ok: true, token: token, expiry: expiry };
}

// credState -> XHR descriptor.
function buildXhr(credState, config) {
    if (!credState || !credState.token) return null;
    var project = (config && config.geminiProject) ? config.geminiProject : "";
    return {
        url: ENDPOINT,
        method: "POST",
        headers: {
            "Authorization": "Bearer " + credState.token,
            "Content-Type": "application/json"
        },
        body: JSON.stringify({ project: project, userAgent: "plasma-agent-usage" })
    };
}

// "REQUESTS" + "gemini-3.1-pro-preview" -> "REQUESTS · gemini-3.1-pro-preview"
function labelFor(bucket) {
    var tokenType = bucket.tokenType || "";
    var modelId = bucket.modelId || "";
    if (tokenType && modelId) return tokenType + " · " + modelId;
    return tokenType || modelId || "quota";
}

// bucket -> window. percent = (1 - remainingFraction) * 100 (clamped by Usage.makeWindow).
function windowFrom(bucket) {
    if (!bucket || typeof bucket !== "object") return null;
    var fraction = Number(bucket.remainingFraction);
    if (isNaN(fraction)) fraction = 0;
    var percent = (1 - fraction) * 100;
    var label = labelFor(bucket);
    var key = label;
    return Usage.makeWindow(key, label, percent, bucket.resetTime || null);
}

// httpStatus + body + header-getter + credState -> UsageModel
function parseUsage(httpStatus, responseText, getHeader, credState) {
    var base = { displayName: displayName, plan: "", source: source };

    if (httpStatus === 401 || httpStatus === 403) {
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

    var buckets = data && data.buckets;
    if (!Array.isArray(buckets) || buckets.length === 0) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "No quota buckets"
        }));
    }

    var windows = [];
    for (var i = 0; i < buckets.length; i++) {
        var w = windowFrom(buckets[i]);
        if (w) windows.push(w);
    }

    if (windows.length === 0) {
        return Usage.makeModel(id, Object.assign({}, base, {
            state: Usage.STATE.error, error: "No quota buckets"
        }));
    }

    return Usage.makeModel(id, Object.assign({}, base, {
        state: Usage.STATE.ok,
        plan: "Free (endpoint)",
        windows: windows,
        models: [],
        lastSuccess: Date.now()
    }));
}
