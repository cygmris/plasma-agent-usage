/*
    Pure-JS unit tests for GeminiAdapter + smoke checks for gemini_count.py.
    Node built-in only — run with: node tests/gemini_test.mjs
*/

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadQmlJs } from "./_qmljs.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const { STATE } = loadQmlJs(resolve(__dirname, "../contents/ui/lib/usage.js"));
const Gemini = loadQmlJs(resolve(__dirname, "../contents/ui/adapters/GeminiAdapter.js"));
const HELPER = join(__dirname, "..", "contents", "code", "gemini_count.py");

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

console.log("GeminiAdapter");

// Synthetic helper JSON (matches design.md contract).
const RESET_ISO = "2026-06-17T00:00:00+08:00";
const HELPER_OK = JSON.stringify({
    ok: true,
    account: "user@gmail.com",
    tier: "oauth-personal",
    tierLabel: "Free",
    dailyLimit: 1000,
    requestsToday: 120,
    requestsTotal: 5000,
    resetAt: RESET_ISO
});

test("adapter identity", () => {
    assert.equal(Gemini.id, "gemini");
    assert.equal(Gemini.displayName, "Gemini");
    assert.equal(Gemini.iconName, "gemini.svg");
    assert.equal(Gemini.source, "local");
});

test("credentialCmd uses config.scriptPath", () => {
    const cmd = Gemini.credentialCmd({ scriptPath: "/x/gemini_count.py" });
    assert.ok(/python3 '\/x\/gemini_count\.py' 2>\/dev\/null/.test(cmd));
});

test("credentialCmd empty when no scriptPath", () => {
    assert.equal(Gemini.credentialCmd({}), "");
    assert.equal(Gemini.credentialCmd(null), "");
});

test("parseCredential ok -> account + plan", () => {
    const c = Gemini.parseCredential(HELPER_OK, {});
    assert.equal(c.ok, true);
    assert.equal(c.account, "user@gmail.com");
    assert.equal(c.plan, "Free");
});

test("parseCredential ok:false -> notLoggedIn", () => {
    const c = Gemini.parseCredential(JSON.stringify({ ok: false, reason: "no-gemini" }), {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.notLoggedIn);
});

test("parseCredential empty -> notLoggedIn (no throw)", () => {
    const c = Gemini.parseCredential("", {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.notLoggedIn);
});

test("parseCredential garbage -> notLoggedIn (no throw)", () => {
    const c = Gemini.parseCredential("not json", {});
    assert.equal(c.ok, false);
    assert.equal(c.state, STATE.notLoggedIn);
});

test("parseUsage ok -> daily window percent=12, label, plan=Free", () => {
    const cred = Gemini.parseCredential(HELPER_OK, {});
    const m = Gemini.parseUsage(200, HELPER_OK, () => null, cred);
    assert.equal(m.id, "gemini");
    assert.equal(m.state, STATE.ok);
    assert.equal(m.source, "local");
    assert.equal(m.plan, "Free");
    assert.equal(m.windows.length, 1);
    const daily = m.windows[0];
    assert.equal(daily.key, "daily");
    assert.equal(daily.label, "Daily (requests)");
    assert.equal(daily.percent, 12);          // 120 / 1000 * 100
    assert.equal(daily.resetAt, RESET_ISO);
});

test("parseUsage ok:false JSON -> notLoggedIn (no throw)", () => {
    const m = Gemini.parseUsage(200, JSON.stringify({ ok: false, reason: "no-gemini" }), () => null, null);
    assert.equal(m.state, STATE.notLoggedIn);
});

test("parseUsage empty -> notLoggedIn (no throw)", () => {
    const m = Gemini.parseUsage(200, "", () => null, null);
    assert.equal(m.state, STATE.notLoggedIn);
});

test("parseUsage garbage -> error (no throw)", () => {
    const m = Gemini.parseUsage(200, "<<<not json>>>", () => null, null);
    assert.equal(m.state, STATE.error);
});

test("parseUsage zero dailyLimit -> percent 0 (no divide-by-zero)", () => {
    const body = JSON.stringify({ ok: true, dailyLimit: 0, requestsToday: 5, tierLabel: "Free", resetAt: RESET_ISO });
    const m = Gemini.parseUsage(200, body, () => null, null);
    assert.equal(m.state, STATE.ok);
    assert.equal(m.windows[0].percent, 0);
});

console.log("\nhelper gemini_count.py");

test("helper runs on real ~/.gemini -> valid JSON with ok field", () => {
    const out = execFileSync("python3", [HELPER], { encoding: "utf8" });
    const data = JSON.parse(out);
    assert.ok(Object.prototype.hasOwnProperty.call(data, "ok"));
});

test("helper counts a today response in a fake HOME -> requestsToday>=1", () => {
    const fakeHome = mkdtempSync(join(tmpdir(), "geminihome-"));
    try {
        const chatsDir = join(fakeHome, ".gemini", "tmp", "proj", "chats");
        mkdirSync(chatsDir, { recursive: true });

        const header = JSON.stringify({
            sessionId: "test-sess",
            startTime: "2026-01-01T00:00:00.000Z",
            kind: "main"
        });
        const todayIso = new Date().toISOString();
        const msg = JSON.stringify({ type: "gemini", timestamp: todayIso });
        writeFileSync(join(chatsDir, "session-x.jsonl"), header + "\n" + msg + "\n");

        writeFileSync(
            join(fakeHome, ".gemini", "settings.json"),
            JSON.stringify({ security: { auth: { selectedType: "oauth-personal" } } })
        );

        const out = execFileSync("python3", [HELPER], {
            encoding: "utf8",
            env: Object.assign({}, process.env, { HOME: fakeHome })
        });
        const data = JSON.parse(out);
        assert.equal(data.ok, true);
        assert.equal(data.tierLabel, "Free");
        assert.equal(data.dailyLimit, 1000);
        assert.ok(data.requestsToday >= 1, "expected requestsToday>=1, got " + data.requestsToday);
    } finally {
        rmSync(fakeHome, { recursive: true, force: true });
    }
});

console.log("\n" + passed + " passed");
