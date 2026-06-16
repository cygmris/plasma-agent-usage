.pragma library
/*
    SPDX-FileCopyrightText: 2025 izll, 2026 Chris
    SPDX-License-Identifier: GPL-3.0-or-later

    Shared usage layer: UsageModel factory + render helpers.

    QML JS library (`.pragma library` + plain functions), loaded from QML via
    `import "lib/usage.js" as Usage`. Node unit tests load it through the
    tests/_qmljs.mjs shim. No QML runtime dependency: color helpers return
    *semantic* Kirigami.Theme color names, which the QML components map to
    concrete colors.
*/

// UsageModel.state enum
var STATE = {
    ok: "ok",
    loading: "loading",
    notLoggedIn: "notLoggedIn",
    tokenError: "tokenError",
    rateLimited: "rateLimited",
    error: "error",
    disabled: "disabled"
};

// Semantic color names (resolved to Kirigami.Theme.<name> by QML components)
var COLOR = {
    ok: "positiveTextColor",
    warn: "neutralTextColor",
    danger: "negativeTextColor"
};

function clampPercent(n) {
    var v = Number(n);
    if (isNaN(v)) return 0;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
}

// Color band: <50 green, <80 yellow, >=80 red (matches baseline getUsageColor)
function usageColor(percent) {
    var p = Number(percent);
    if (isNaN(p)) p = 0;
    if (p < 50) return COLOR.ok;
    if (p < 80) return COLOR.warn;
    return COLOR.danger;
}

// makeWindow(key, label, percent, resetAtIso, resetLabel?)
function makeWindow(key, label, percent, resetAtIso, resetLabel) {
    return {
        key: key,
        label: label,
        percent: clampPercent(percent),
        resetAt: resetAtIso || null,
        resetLabel: resetLabel || ""
    };
}

function makeModelUsage(label, percent) {
    return {
        label: label,
        percent: clampPercent(percent)
    };
}

// makeModel(id, fields) — fields override defaults
function makeModel(id, fields) {
    var m = {
        id: id,
        displayName: "",
        plan: "",
        state: STATE.loading,
        source: "endpoint",
        windows: [],
        models: [],
        error: "",
        lastSuccess: 0,
        isStale: false
    };
    if (fields) {
        for (var k in fields) {
            if (fields.hasOwnProperty(k)) m[k] = fields[k];
        }
    }
    return m;
}

// formatRemaining(resetAtIso, nowMs?) -> "2d 3h" / "3h 12m" / "12m" / ""
// Uses short unit suffixes (d/h/m); QML side may localize separately.
function formatRemaining(resetAtIso, nowMs) {
    if (!resetAtIso) return "";
    var reset = new Date(resetAtIso).getTime();
    if (isNaN(reset)) return "";
    var now = (typeof nowMs === "number") ? nowMs : Date.now();
    var diff = reset - now;
    if (diff <= 0) return "";

    var hours = Math.floor(diff / (1000 * 60 * 60));
    var minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

    if (hours > 24) {
        var days = Math.floor(hours / 24);
        hours = hours % 24;
        return days + "d " + hours + "h";
    } else if (hours > 0) {
        return hours + "h " + minutes + "m";
    } else {
        return minutes + "m";
    }
}
