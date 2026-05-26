# Zotero Paper Summarizer

Summarize academic papers using Claude CLI custom slash commands.

---

## ⚠️ Editing the script — READ THIS FIRST

Zotero's Actions & Tags plugin imports actions from a YAML backup
(`zotero-summrarize-paper-action.yml`). That YAML has the JavaScript embedded
inside its `data: |` block.

Editing JS inside a YAML block scalar is miserable, so the JS lives in a
plain `.js` file and we splice it into the YAML before importing:

```
zotero_summarizer_action.js          ← source of truth (edit here)
zotero-summrarize-paper-action.yml   ← generated; what Zotero imports
build_yaml.py                        ← splicer
```

**After any edit to a `*_action.js` file (including AI-driven edits) you MUST
re-run the builder before re-importing into Zotero — otherwise Zotero loads
the stale YAML.**

```bash
cd all/code-agents/paper-summarization
python3 build_yaml.py zotero_summarizer_action.js \
                      zotero-summrarize-paper-action.yml
```

The builder swaps just the `data:` block of the target YAML; metadata (action
id, event, operation, menu config) is preserved untouched. Idempotent — safe
to re-run.

---

## Setup

### 0. Install Node.js (only if your Claude CLI is a node-shim install)

The current macOS install ships `claude` as a native Mach-O binary, so node is
not required. If you installed via `npm install -g @anthropic-ai/claude-code`
on a different OS, you also need node:

- Linux (Debian/Ubuntu): `sudo apt-get install nodejs npm`
- Windows (winget): `winget install OpenJS.NodeJS.LTS`

### 1. Install Claude CLI

```bash
# macOS / Linux native installer
curl -fsSL https://claude.ai/install.sh | bash
# or, npm-based
npm install -g @anthropic-ai/claude-code
```

`claude` must end up on PATH for the Zotero subprocess. Our bootstrap places
it at `~/.local/bin/claude`; the script's macOS branch prepends
`~/.local/bin` to PATH before invoking it.

### 2. Link Your Prompts Directory

```bash
# Linux/macOS
ln -s /path/to/your/prompts ~/.claude/commands

# Windows (PowerShell as Admin)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\commands" \
    -Target "C:\path\to\prompts"
```

(In this repo: `install.py` already symlinks `all/code-agents/prompts` →
`~/.claude/commands`.)

### 3. Test the CLI side

```bash
claude -p "/summarize-paper /path/to/paper.pdf" --add-dir /path/to
```

### 4. Zotero Setup

1. Install [zotero-actions-tags](https://github.com/windingwind/zotero-actions-tags/releases)
2. Tools → Actions & Tags Settings
3. Click the **Import** icon and choose
   `zotero-summrarize-paper-action.yml`
4. Save

After editing the JS later, **delete the old action first, then re-import**
the regenerated YAML — Actions & Tags treats imports as additive, so without
deleting you'd end up with two copies running on the same event.

## Configuration

Edit `CONFIG.command` at the top of the JS file to point at a different
prompt under your commands directory. Then run `build_yaml.py` and re-import.

## Creating Prompts

Add `.md` files to your prompts directory:

```markdown
---
description: My summary prompt
allowed-tools: Read
---

Read the PDF at: $ARGUMENTS

Your prompt here...
```

## Sources

- [Claude Code Slash Commands](https://code.claude.com/docs/en/slash-commands)
- [Zotero Actions & Tags](https://github.com/windingwind/zotero-actions-tags)
