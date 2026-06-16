/*
    Pure-JS unit tests for CodexAdapter.
    Node built-in only — run with: node tests/codex_test.mjs
*/

import assert from "node:assert/strict";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./_qmljs.mjs";
const __dirname = dirname(fileURLToPath(import.meta.url));
const { STATE } = loadQmlJs(resolve(__dirname, "../contents/ui/lib/usage.js"));
const Codex = loadQmlJs(resolve(__dirname, "../contents/ui/adapters/CodexAdapter.js"));

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

console.log("CodexAdapter");

// Real /wham/usage 200 fixture (verbatim from design.md)
const FIXTURE_200 = '{"plan_type":"pro","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":3,"limit_window_seconds":18000,"reset_after_seconds":13876,"reset_at":1781597404},"secondary_window":{"used_percent":36,"limit_window_seconds":604800,"reset_after_seconds":176360,"reset_at":1781759888}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":{"allowed":true,"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_at":1781601529},"secondary_window":{"used_percent":2,"limit_window_seconds":604800,"reset_at":1782106257}}}],"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"rate_limit_reached_type":null}';

const CRED = { ok: true, accessToken: "tok-x", accountId: "acct-1", plan: "" };

test("adapter identity", () => {
    assert.equal(Codex.id, "codex");
    assert.equal(Codex.displayName, "Codex");
    assert.equal(Codex.iconName, "codex.svg");
    assert.equal(Codex.source, "endpoint");
});

test("credentialCmd reads ~/.codex/auth.json", () => {
    assert.ok(/\.codex\/auth\.json/.test(Codex.credentialCmd({})));
});

test("parseCredential chatgpt mode -> ok + token + accountId", () => {
    const stdout = JSON.stringify({
        auth_mode: "chatgpt",
        tokens: { access_token: "AT", account_id: "ACC", id_token: "x", refresh_token: "y" }
    });
    const r = Codex.parseCredential(stdout, {});
    assert.equal(r.ok, true);
    assert.equal(r.accessToken, "AT");
    assert.equal(r.accountId, "ACC");
});

test("parseCredential apikey mode -> disabled + note", () => {
    const stdout = JSON.stringify({ auth_mode: "apikey", tokens: {} });
    const r = Codex.parseCredential(stdout, {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.disabled);
    assert.ok(r.note && r.note.length > 0);
});

test("parseCredential empty -> notLoggedIn (no throw)", () => {
    const r = Codex.parseCredential("", {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.notLoggedIn);
});

test("parseCredential garbage -> notLoggedIn (no throw)", () => {
    const r = Codex.parseCredential("not json at all", {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.notLoggedIn);
});

test("parseCredential chatgpt but no token -> notLoggedIn", () => {
    const stdout = JSON.stringify({ auth_mode: "chatgpt", tokens: {} });
    const r = Codex.parseCredential(stdout, {});
    assert.equal(r.ok, false);
    assert.equal(r.state, STATE.notLoggedIn);
});

test("buildXhr GET with required headers", () => {
    const x = Codex.buildXhr(CRED, {});
    assert.equal(x.method, "GET");
    assert.equal(x.url, "https://chatgpt.com/backend-api/wham/usage");
    assert.equal(x.headers["Authorization"], "Bearer tok-x");
    assert.equal(x.headers["ChatGPT-Account-Id"], "acct-1");
    assert.equal(x.headers["User-Agent"], "codex-cli");
    assert.equal(x.headers["Accept"], "application/json");
});

test("buildXhr null when no token", () => {
    assert.equal(Codex.buildXhr({ accessToken: "" }, {}), null);
    assert.equal(Codex.buildXhr(null, {}), null);
});

test("parseUsage 200 -> 2 windows, percent/label/resetAt/plan", () => {
    const m = Codex.parseUsage(200, FIXTURE_200, () => null, CRED);
    assert.equal(m.id, "codex");
    assert.equal(m.state, STATE.ok);
    assert.equal(m.plan, "Pro");
    assert.equal(m.source, "endpoint");
    assert.equal(m.windows.length, 2);

    const primary = m.windows.find(w => w.key === "primary");
    assert.equal(primary.percent, 3);
    assert.equal(primary.label, "Session (5h)");
    assert.equal(primary.resetAt, new Date(1781597404 * 1000).toISOString());

    const secondary = m.windows.find(w => w.key === "secondary");
    assert.equal(secondary.percent, 36);
    assert.equal(secondary.label, "Weekly (7d)");
    assert.equal(secondary.resetAt, new Date(1781759888 * 1000).toISOString());
});

test("parseUsage 401 -> tokenError", () => {
    const m = Codex.parseUsage(401, "", () => null, CRED);
    assert.equal(m.state, STATE.tokenError);
});

test("parseUsage 429 -> rateLimited + retryAfter", () => {
    const getHeader = (h) => (h === "retry-after" ? "90" : null);
    const m = Codex.parseUsage(429, "", getHeader, CRED);
    assert.equal(m.state, STATE.rateLimited);
    assert.equal(m.retryAfter, 90);
});

test("parseUsage 500 -> error", () => {
    const m = Codex.parseUsage(500, "", () => null, CRED);
    assert.equal(m.state, STATE.error);
});

test("parseUsage non-JSON 200 -> error (no throw)", () => {
    const m = Codex.parseUsage(200, "<<<not json>>>", () => null, CRED);
    assert.equal(m.state, STATE.error);
});

test("parseUsage missing secondary_window -> 1 window, no crash", () => {
    const body = JSON.stringify({
        plan_type: "plus",
        rate_limit: {
            primary_window: { used_percent: 10, limit_window_seconds: 18000, reset_at: 1781597404 }
        }
    });
    const m = Codex.parseUsage(200, body, () => null, CRED);
    assert.equal(m.state, STATE.ok);
    assert.equal(m.plan, "Plus");
    assert.equal(m.windows.length, 1);
    assert.equal(m.windows[0].key, "primary");
});

test("parseUsage missing rate_limit -> error", () => {
    const body = JSON.stringify({ plan_type: "pro" });
    const m = Codex.parseUsage(200, body, () => null, CRED);
    assert.equal(m.state, STATE.error);
});

test("parseUsage unknown plan_type -> capitalized fallback", () => {
    const body = JSON.stringify({
        plan_type: "scale",
        rate_limit: { primary_window: { used_percent: 1, limit_window_seconds: 18000, reset_at: 1781597404 } }
    });
    const m = Codex.parseUsage(200, body, () => null, CRED);
    assert.equal(m.plan, "Scale");
});

test("labelFor fallback for non-standard window seconds", () => {
    const body = JSON.stringify({
        plan_type: "pro",
        rate_limit: {
            primary_window: { used_percent: 5, limit_window_seconds: 3600, reset_at: 1781597404 },
            secondary_window: { used_percent: 5, limit_window_seconds: 259200, reset_at: 1781759888 }
        }
    });
    const m = Codex.parseUsage(200, body, () => null, CRED);
    assert.equal(m.windows[0].label, "1h");
    assert.equal(m.windows[1].label, "3d");
});

console.log("\n" + passed + " passed");
