#!/usr/bin/env python3
"""
PreToolUse hook: auto-approve `bq query` invocations whose SQL is
demonstrably read-only — including the common pattern of dumping the
result to a temp file and then reading it, e.g.:

    bq query 'SELECT ...' > /tmp/foo && head -100 /tmp/foo

Strategy
--------
1. Split the command line at top-level shell chain operators (&&, ||, ;)
   while respecting single/double quotes. Refuse to parse commands that
   contain backtick or `$(...)` substitution (out-of-scope for safety).
2. The FIRST chain element must look exactly like
     bq query [flags] 'SQL' [optional redirect]
   with no shell injection between `bq query` and the SQL.
3. The SQL must start with SELECT / WITH / EXPLAIN / DESCRIBE (after
   stripping leading `/* */` and `-- ` comments) and contain no mutating
   keyword anywhere (CREATE / INSERT / UPDATE / DELETE / MERGE / DROP /
   ALTER / TRUNCATE / REPLACE / GRANT / REVOKE).
4. If there ARE further chained commands, hand them to Dippy as a fresh
   shell command line. Dippy already knows which commands are read-only;
   we only auto-approve if Dippy says `allow` for the rest.

Acceptable false negatives:
  * SELECT with a string literal containing the word "DROP" → falls
    through (we don't parse SQL string literals).
  * Trailing flags after the SQL (`bq query 'SELECT 1' --format csv`)
    → falls through. Easy to add later.

macOS system python is 3.9.6; no PEP 604 syntax.
"""
import json
import os
import re
import subprocess
import sys

DIPPY_BIN = os.path.expanduser("~/.local/share/dippy/bin/dippy-hook")

READ_ONLY_HEAD_RE = re.compile(
    r"^\s*(?:SELECT|WITH|EXPLAIN|DESCRIBE)\b",
    re.IGNORECASE,
)

MUTATING_RE = re.compile(
    r"\b(?:CREATE|INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|TRUNCATE|REPLACE|GRANT|REVOKE)\b",
    re.IGNORECASE,
)

# bq query [flags] 'SQL' [optional redirect to file path]. Nothing else.
FIRST_BQ_RE = re.compile(
    r"""
    ^\s*bq\s+query\s+
    (?:
        -{1,2}[A-Za-z][A-Za-z0-9_-]*
        (?: = [^\s'"]+ | \s+ (?!-) [^\s'"]+ )?
        \s+
    )*
    (?: ' ([^']*) ' | " ([^"]*) " )
    \s*
    (?: >>? \s* [/A-Za-z0-9_.\-]+ )?
    \s*$
    """,
    re.VERBOSE,
)


def strip_sql_lead_comments(s):
    """Strip leading /* */ and -- comments and whitespace."""
    s = s.lstrip()
    while True:
        if s.startswith("/*"):
            end = s.find("*/")
            if end < 0:
                return ""
            s = s[end + 2:].lstrip()
        elif s.startswith("--"):
            eol = s.find("\n")
            s = s[eol + 1:].lstrip() if eol >= 0 else ""
        else:
            return s


def is_safe_bq_part(part):
    """True if `part` (one chain element) is a safe `bq query SELECT/...` call."""
    m = FIRST_BQ_RE.match(part)
    if not m:
        return False
    sql = m.group(1) if m.group(1) is not None else m.group(2)

    head = strip_sql_lead_comments(sql)
    if not READ_ONLY_HEAD_RE.match(head):
        return False
    if MUTATING_RE.search(sql):
        return False
    return True


def split_chain(cmd):
    """
    Split at top-level && / || / ; respecting '...' and "..." quoting.
    Returns a list of (part, separator_before_this_part_or_None) or None
    if the command can't be safely parsed (unterminated quotes, command
    substitution, etc.).
    """
    parts = []
    sep = None
    buf = []
    in_single = False
    in_double = False
    i = 0
    n = len(cmd)
    while i < n:
        c = cmd[i]
        if in_single:
            buf.append(c)
            if c == "'":
                in_single = False
            i += 1
            continue
        if in_double:
            buf.append(c)
            if c == '"' and (i == 0 or cmd[i - 1] != '\\'):
                in_double = False
            i += 1
            continue
        if c == "'":
            in_single = True
            buf.append(c)
            i += 1
            continue
        if c == '"':
            in_double = True
            buf.append(c)
            i += 1
            continue
        if c == "`" or cmd[i:i + 2] == "$(":
            return None  # command substitution: out-of-scope
        if cmd[i:i + 2] in ("&&", "||"):
            parts.append(("".join(buf).strip(), sep))
            sep = cmd[i:i + 2]
            buf = []
            i += 2
            continue
        if c == ";":
            parts.append(("".join(buf).strip(), sep))
            sep = ";"
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if in_single or in_double:
        return None
    parts.append(("".join(buf).strip(), sep))
    return [p for p in parts if p[0]]  # drop empty pieces


def call_dippy(cmd):
    """Subprocess Dippy; return ('allow'|'ask'|'deny'|None, reason_or_None)."""
    if not os.access(DIPPY_BIN, os.X_OK):
        return (None, None)
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    try:
        proc = subprocess.run(
            [DIPPY_BIN],
            input=payload,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return (None, None)
    if not proc.stdout.strip():
        return (None, None)
    try:
        data = json.loads(proc.stdout)
    except Exception:
        return (None, None)
    h = data.get("hookSpecificOutput", {}) or {}
    return (h.get("permissionDecision"), h.get("permissionDecisionReason"))


def join_rest(rest):
    """Rebuild a shell command line from chain parts after the first."""
    pieces = []
    for i, (part, sep) in enumerate(rest):
        if i > 0 and sep:
            pieces.append(sep)
        pieces.append(part)
    return " ".join(pieces)


def classify(cmd):
    """Return (head_keyword, dippy_reason_or_None) on allow, else None."""
    parts = split_chain(cmd)
    if not parts:
        return None

    first_part, _ = parts[0]
    if not is_safe_bq_part(first_part):
        return None

    # Recover the keyword for the reason string
    m = FIRST_BQ_RE.match(first_part)
    sql = m.group(1) if m.group(1) is not None else m.group(2)
    head = strip_sql_lead_comments(sql)
    head_kw = READ_ONLY_HEAD_RE.match(head).group(0).strip().upper()

    if len(parts) == 1:
        return (head_kw, None)

    rest_cmd = join_rest(parts[1:])
    decision, reason = call_dippy(rest_cmd)
    if decision != "allow":
        return None
    return (head_kw, reason)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    cmd = payload.get("tool_input", {}).get("command", "")
    if not cmd:
        return
    result = classify(cmd)
    if result is None:
        return
    head_kw, dippy_reason = result
    reason = "bq query is read-only ({})".format(head_kw)
    if dippy_reason:
        reason += "; chained: " + dippy_reason
    json.dump({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }
    }, sys.stdout)


if __name__ == "__main__":
    main()
