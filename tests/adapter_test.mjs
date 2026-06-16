/*
    Pure-JS unit tests for the shared usage layer + ClaudeAdapter.
    Node built-in only — run with: node tests/adapter_test.mjs
*/

import assert from "node:assert/strict";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./_qmljs.mjs";
const __dirname = dirname(fileURLToPath(import.meta.url));
const {
    usageColor, clampPercent, formatRemaining, COLOR, STATE
} = loadQmlJs(resolve(__dirname, "../contents/ui/lib/usage.js"));
const Claude = loadQmlJs(resolve(__dirname, "../contents/ui/adapters/ClaudeAdapter.js"));

let passed = 0;
function test(name, fn) {
    try {
        fn();
        passed++;
        console.log("  ok - " + name);
    } catch (e) {
        console.error("  FAIL - " + name);
        console.error("        " + (e && e.message ? e.message : e));
        process.exitCode = 1;
    }
}

console.log("usage.js");

test("usageColor band 49 -> ok (green)", () => {
    assert.equal(usageColor(49), COLOR.ok);
});
test("usageColor band 50 -> warn (yellow)", () => {
    assert.equal(usageColor(50), COLOR.warn);
});
test("usageColor band 79 -> warn (yellow)", () => {
    assert.equal(usageColor(79), COLOR.warn);
});
test("usageColor band 80 -> danger (red)", () => {
    assert.equal(usageColor(80), COLOR.danger);
});
test("usageColor 0 -> ok", () => {
    assert.equal(usageColor(0), COLOR.ok);
});

test("clampPercent clamps range and NaN", () => {
    assert.equal(clampPercent(-5), 0);
    assert.equal(clampPercent(150), 100);
    assert.equal(clampPercent(42), 42);
    assert.equal(clampPercent("x"), 0);
});

test("formatRemaining empty for null/past", () => {
    assert.equal(formatRemaining(null), "");
    const past = new Date(Date.now() - 1000).toISOString();
    assert.equal(formatRemaining(past), "");
});
test("formatRemaining minutes only", () => {
    const now = Date.UTC(2025, 0, 1, 0, 0, 0);
    const reset = new Date(Date.UTC(2025, 0, 1, 0, 30, 0)).toISOString();
    assert.equal(formatRemaining(reset, now), "30m");
});
test("formatRemaining hours and minutes", () => {
    const now = Date.UTC(2025, 0, 1, 0, 0, 0);
    const reset = new Date(Date.UTC(2025, 0, 1, 3, 15, 0)).toISOString();
    assert.equal(formatRemaining(reset, now), "3h 15m");
});
test("formatRemaining days and hours", () => {
    const now = Date.UTC(2025, 0, 1, 0, 0, 0);
    const reset = new Date(Date.UTC(2025, 0, 3, 5, 0, 0)).toISOString();
    assert.equal(formatRemaining(reset, now), "2d 5h");
});

console.log("ClaudeAdapter");

const SAMPLE_200 = JSON.stringify({
    five_hour: { utilization: 14.0, resets_at: "2025-11-29T19:00:00+00:00" },
    seven_day: { utilization: 89.0, resets_at: "2025-12-01T19:00:00+00:00" },
    seven_day_sonnet: { utilization: 31.0, resets_at: "2025-12-01T19:00:00+00:00" },
    seven_day_opus: { utilization: 5.0, resets_at: "2025-12-01T19:00:00+00:00" }
});

const CRED = { ok: true, accessToken: "sk-ant-oat01-x", plan: "Max 20x", tier: "default_claude_max_20x" };

test("adapter identity", () => {
    assert.equal(Claude.id, "claude");
    assert.equal(Claude.source, "endpoint");
    assert.equal(Claude.iconName, "claude.svg");
});

test("parseCredential ok + tier->plan", () => {
    const stdout = JSON.stringify({
        claudeAiOauth: { accessToken: "sk-ant-oat01-abc", rateLimitTier: "default_claude_max_5x" }
    });
    const r = Claude.parseCredential(stdout, {});
    assert.equal(r.ok, true);
    assert.equal(r.accessToken, "sk-ant-oat01-abc");
    assert.equal(r.plan, "Max 5x");
});
test("parseCredential empty -> notLoggedIn", () => {
    const r = Claude.parseCredential("", {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.notLoggedIn);
});
test("parseCredential garbage -> notLoggedIn (no throw)", () => {
    const r = Claude.parseCredential("not json at all here", {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.notLoggedIn);
});

test("buildXhr GET with required headers", () => {
    const x = Claude.buildXhr(CRED, {});
    assert.equal(x.method, "GET");
    assert.equal(x.url, "https://api.anthropic.com/api/oauth/usage");
    assert.equal(x.headers["anthropic-beta"], "oauth-2025-04-20");
    assert.equal(x.headers["Authorization"], "Bearer sk-ant-oat01-x");
    assert.ok(/^claude-code\//.test(x.headers["User-Agent"]));
});
test("buildXhr null when no token", () => {
    assert.equal(Claude.buildXhr({ accessToken: "" }, {}), null);
});

test("parseUsage 200 -> windows/models/plan/reset", () => {
    const m = Claude.parseUsage(200, SAMPLE_200, () => null, CRED);
    assert.equal(m.id, "claude");
    assert.equal(m.state, STATE.ok);
    assert.equal(m.plan, "Max 20x");
    assert.equal(m.source, "endpoint");
    assert.equal(m.windows.length, 2);

    const session = m.windows.find(w => w.key === "session");
    assert.equal(session.percent, 14);
    assert.equal(session.label, "Session (5hr)");
    assert.equal(session.resetAt, "2025-11-29T19:00:00+00:00");

    const weekly = m.windows.find(w => w.key === "weekly");
    assert.equal(weekly.percent, 89);
    assert.equal(weekly.resetAt, "2025-12-01T19:00:00+00:00");

    assert.equal(m.models.length, 2);
    assert.equal(m.models[0].label, "Sonnet");
    assert.equal(m.models[0].percent, 31);
    assert.equal(m.models[1].label, "Opus");
    assert.equal(m.models[1].percent, 5);
});

test("parseUsage 401 -> tokenError", () => {
    const m = Claude.parseUsage(401, "", () => null, CRED);
    assert.equal(m.state, STATE.tokenError);
});

test("parseUsage 429 -> rateLimited + retryAfter", () => {
    const getHeader = (h) => (h === "retry-after" ? "120" : null);
    const m = Claude.parseUsage(429, "", getHeader, CRED);
    assert.equal(m.state, STATE.rateLimited);
    assert.equal(m.retryAfter, 120);
});

test("parseUsage 200 missing opus -> no crash, 1 model", () => {
    const noOpus = JSON.stringify({
        five_hour: { utilization: 10, resets_at: "2025-11-29T19:00:00+00:00" },
        seven_day: { utilization: 20, resets_at: "2025-12-01T19:00:00+00:00" },
        seven_day_sonnet: { utilization: 12 },
        seven_day_opus: null
    });
    const m = Claude.parseUsage(200, noOpus, () => null, CRED);
    assert.equal(m.state, STATE.ok);
    assert.equal(m.models.length, 1);
    assert.equal(m.models[0].label, "Sonnet");
});

test("parseUsage 200 missing all model fields -> empty models, no crash", () => {
    const minimal = JSON.stringify({
        five_hour: { utilization: 3 },
        seven_day: { utilization: 7 }
    });
    const m = Claude.parseUsage(200, minimal, () => null, CRED);
    assert.equal(m.state, STATE.ok);
    assert.equal(m.models.length, 0);
    assert.equal(m.windows.length, 2);
    assert.equal(m.windows[0].resetAt, null);
});

test("parseUsage 500 -> error state", () => {
    const m = Claude.parseUsage(500, "", () => null, CRED);
    assert.equal(m.state, STATE.error);
});

console.log("\n" + passed + " passed");
