/*
    Pure-JS unit tests for GeminiEndpointAdapter (opt-in endpoint mode).
    Node built-in only — run with: node tests/gemini_endpoint_test.mjs

    SAFETY: these tests NEVER hit the real cloudcode-pa.googleapis.com endpoint.
    They feed synthetic fixtures straight into parseUsage/parseCredential.
*/

import assert from "node:assert/strict";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./_qmljs.mjs";
const __dirname = dirname(fileURLToPath(import.meta.url));
const { STATE } = loadQmlJs(resolve(__dirname, "../contents/ui/lib/usage.js"));
const GE = loadQmlJs(resolve(__dirname, "../contents/ui/adapters/GeminiEndpointAdapter.js"));

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

console.log("GeminiEndpointAdapter");

// Synthetic retrieveUserQuota 200 response (research shape, not live-verified).
// One partly-used REQUESTS bucket + one full bucket missing remainingAmount.
const RESET_ISO = "2025-12-10T22:19:52Z";
const QUOTA_200 = JSON.stringify({
    buckets: [
        {
            modelId: "gemini-3.1-pro-preview",
            tokenType: "REQUESTS",
            remainingFraction: 0.76175,
            resetTime: RESET_ISO
        },
        {
            modelId: "gemini-3.1-flash",
            tokenType: "REQUESTS",
            remainingFraction: 1,
            resetTime: RESET_ISO
        }
    ]
});

test("adapter identity", () => {
    assert.equal(GE.id, "gemini");
    assert.equal(GE.displayName, "Gemini");
    assert.equal(GE.iconName, "gemini.svg");
    assert.equal(GE.source, "endpoint");
});

test("credentialCmd reads ~/.gemini/oauth_creds.json", () => {
    const cmd = GE.credentialCmd({});
    assert.ok(/cat \$HOME\/\.gemini\/oauth_creds\.json 2>\/dev\/null/.test(cmd));
});

test("parseCredential valid token -> ok", () => {
    const future = Date.now() + 3600 * 1000;
    const c = GE.parseCredential(JSON.stringify({ access_token: "ya29.x", expiry_date: future }), {});
    assert.equal(c.ok, true);
    assert.equal(c.token, "ya29.x");
});

test("parseCredential expired expiry_date -> tokenError", () => {
    const past = Date.now() - 1000;
    const c = GE.parseCredential(JSON.stringify({ access_token: "ya29.x", expiry_date: past }), {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.tokenError);
});

test("parseCredential empty -> notLoggedIn (no throw)", () => {
    const c = GE.parseCredential("", {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.notLoggedIn);
});

test("parseCredential garbage -> notLoggedIn (no throw)", () => {
    const c = GE.parseCredential("not json", {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.notLoggedIn);
});

test("buildXhr POSTs to retrieveUserQuota with bearer + project body", () => {
    const xhr = GE.buildXhr({ token: "ya29.x" }, { geminiProject: "my-proj" });
    assert.equal(xhr.method, "POST");
    assert.ok(/retrieveUserQuota$/.test(xhr.url));
    assert.equal(xhr.headers["Authorization"], "Bearer ya29.x");
    assert.equal(xhr.headers["Content-Type"], "application/json");
    const body = JSON.parse(xhr.body);
    assert.equal(body.project, "my-proj");
    assert.equal(body.userAgent, "plasma-agent-usage");
});

test("buildXhr no token -> null", () => {
    assert.equal(GE.buildXhr({}, {}), null);
    assert.equal(GE.buildXhr(null, {}), null);
});

test("buildXhr default empty project when unset", () => {
    const xhr = GE.buildXhr({ token: "ya29.x" }, {});
    assert.equal(JSON.parse(xhr.body).project, "");
});

test("parseUsage 200 -> windows percent ~24 and full=0, label, resetAt", () => {
    const m = GE.parseUsage(200, QUOTA_200, () => null, { token: "ya29.x" });
    assert.equal(m.id, "gemini");
    assert.equal(m.state, STATE.ok);
    assert.equal(m.source, "endpoint");
    assert.equal(m.plan, "Free (endpoint)");
    assert.equal(m.windows.length, 2);

    const partial = m.windows[0];
    assert.equal(partial.label, "REQUESTS · gemini-3.1-pro-preview");
    assert.equal(partial.key, "REQUESTS · gemini-3.1-pro-preview");
    assert.ok(Math.abs(partial.percent - 23.825) < 0.01, "expected ~23.825, got " + partial.percent);
    assert.equal(Math.round(partial.percent), 24);
    assert.equal(partial.resetAt, RESET_ISO);

    const full = m.windows[1];
    assert.equal(full.percent, 0);   // remainingFraction 1, remainingAmount absent -> no crash
    assert.equal(full.label, "REQUESTS · gemini-3.1-flash");
});

test("parseUsage 401 -> tokenError", () => {
    const m = GE.parseUsage(401, "", () => null, null);
    assert.equal(m.state, STATE.tokenError);
});

test("parseUsage 429 -> rateLimited", () => {
    const m = GE.parseUsage(429, "", (h) => (h === "retry-after" ? "30" : null), null);
    assert.equal(m.state, STATE.rateLimited);
    assert.equal(m.retryAfter, 30);
});

test("parseUsage empty buckets -> error", () => {
    const m = GE.parseUsage(200, JSON.stringify({ buckets: [] }), () => null, null);
    assert.equal(m.state, STATE.error);
});

test("parseUsage missing buckets -> error", () => {
    const m = GE.parseUsage(200, JSON.stringify({}), () => null, null);
    assert.equal(m.state, STATE.error);
});

test("parseUsage bad JSON -> error (no throw)", () => {
    const m = GE.parseUsage(200, "<<<not json>>>", () => null, null);
    assert.equal(m.state, STATE.error);
});

console.log("\n" + passed + " passed");
