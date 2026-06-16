#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025 izll
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Counts local Gemini CLI requests (ToS-safe, no network) and emits JSON for
# the plasmoid. Trimmed from OhMyToken's gemini_local_stats.py — only the
# counting bits are kept (no token charts / throughput / active-process probe).
#
# Output contract (see design.md):
#   { ok, account, tier, tierLabel, dailyLimit,
#     requestsToday, requestsTotal, resetAt }
#   or { ok: false, reason: "no-gemini" } if ~/.gemini is missing.
#
# A "request" is one Gemini *response* message. The OhMyToken schema marks
# these with type=="gemini"; we also accept role=="model"/"assistant" as a
# defensive fallback, since the local ~/.gemini had no live message data to
# validate against. Both .json and .jsonl session files are handled.

import json
import os
import glob
from datetime import datetime, timedelta, timezone

gemini_dir = os.path.expanduser("~/.gemini")
tmp_dir = os.path.join(gemini_dir, "tmp")
accounts_file = os.path.join(gemini_dir, "google_accounts.json")
settings_file = os.path.join(gemini_dir, "settings.json")


def emit(obj):
    print(json.dumps(obj))


# No Gemini install at all -> not logged in.
if not os.path.isdir(gemini_dir):
    emit({"ok": False, "reason": "no-gemini"})
    raise SystemExit(0)

# --- Local-midnight boundary + next-midnight reset (timezone correct) ---
now_local = datetime.now().astimezone()
local_midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
today_ts = local_midnight.timestamp() * 1000
next_midnight = local_midnight + timedelta(days=1)
reset_at = next_midnight.isoformat()

# Tier table (requests per day) — authoritative per design.md.
TIER_LIMITS = {
    "oauth-personal": {"label": "Free", "requests_per_day": 1000},
    "oauth-workspace-standard": {"label": "Standard", "requests_per_day": 1500},
    "oauth-workspace-enterprise": {"label": "Enterprise", "requests_per_day": 2000},
    "gemini-api-key": {"label": "API Key", "requests_per_day": 250},
}

# --- Account (never logged to stderr) ---
account = ""
try:
    with open(accounts_file) as f:
        acc = json.load(f)
    if isinstance(acc, dict):
        account = acc.get("active", acc.get("email", "")) or ""
    elif isinstance(acc, list) and acc:
        first = acc[0]
        account = first if isinstance(first, str) else first.get("active", first.get("email", ""))
except Exception:
    pass

# --- Tier ---
auth_type = "oauth-personal"
try:
    with open(settings_file) as f:
        settings = json.load(f)
    auth_type = settings.get("security", {}).get("auth", {}).get("selectedType", "oauth-personal")
except Exception:
    pass

tier_info = TIER_LIMITS.get(auth_type, TIER_LIMITS["oauth-personal"])
daily_limit = tier_info["requests_per_day"]
tier_label = tier_info["label"]


def parse_iso_ts(ts_str):
    """ISO8601 string -> epoch milliseconds, 0 on failure."""
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp() * 1000
    except Exception:
        return 0


def is_response(msg):
    """True if this message is a Gemini response (= one API request)."""
    if not isinstance(msg, dict):
        return False
    if msg.get("type") == "gemini":
        return True
    role = msg.get("role")
    return role in ("model", "assistant")


def load_messages(chat_file):
    """Return list of message dicts from a .json or .jsonl session file."""
    with open(chat_file) as f:
        if chat_file.endswith(".jsonl"):
            lines = f.readlines()
            if not lines:
                return []
            # First line is the session header — skip it.
            messages = []
            for line in lines[1:]:
                line = line.strip()
                if not line:
                    continue
                try:
                    messages.append(json.loads(line))
                except Exception:
                    continue
            return messages
        session = json.load(f)
        if isinstance(session, dict):
            return session.get("messages", []) or []
        if isinstance(session, list):
            return session
        return []


requests_today = 0
requests_total = 0

try:
    pattern = os.path.join(tmp_dir, "*", "chats", "session-*.json*")
    for chat_file in glob.glob(pattern):
        try:
            messages = load_messages(chat_file)
        except Exception:
            continue
        for msg in messages:
            if not is_response(msg):
                continue
            requests_total += 1
            ts_str = msg.get("timestamp", "") if isinstance(msg, dict) else ""
            ts_ms = parse_iso_ts(ts_str) if ts_str else 0
            if ts_ms >= today_ts:
                requests_today += 1
except Exception:
    pass

emit({
    "ok": True,
    "account": account,
    "tier": auth_type,
    "tierLabel": tier_label,
    "dailyLimit": daily_limit,
    "requestsToday": requests_today,
    "requestsTotal": requests_total,
    "resetAt": reset_at,
})
