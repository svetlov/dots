# Zotero Paper Summarizer

Summarize academic papers using Claude CLI custom slash commands.

## Setup

### 1. Install Claude CLI

```bash
npm install -g @anthropic-ai/claude-code
```

### 2. Link Your Prompts Directory

```bash
# Linux/macOS
ln -s /path/to/your/prompts ~/.claude/commands

# Windows (PowerShell as Admin)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\commands" -Target "C:\path\to\prompts"
```

### 3. Test

```bash
claude -p "/summarize-paper /path/to/paper.pdf" --add-dir /path/to
```

### 4. Zotero Setup

1. Install [zotero-actions-tags](https://github.com/windingwind/zotero-actions-tags/releases)
2. Tools → Actions & Tags Settings → **+**
3. Set **Operation**: `customScript`, **Menu**: ✓
4. Click **⤤** → paste `zotero_summarizer_action.js`
5. Save

## Configuration

Edit `CONFIG.command` in the JS file to use different prompts from your commands directory.

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
