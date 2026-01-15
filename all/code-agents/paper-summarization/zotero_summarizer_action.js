/**
 * Zotero Actions & Tags - Paper Summarizer
 *
 * Calls Claude CLI with custom slash commands to summarize PDFs.
 *
 * Setup:
 * 1. Symlink prompts: ln -s /path/to/prompts ~/.claude/commands
 * 2. Install zotero-actions-tags plugin
 * 3. Create action with operation "customScript"
 * 4. Paste this script into the "data" field
 */

const CONFIG = {
    // Slash command (must exist in ~/.claude/commands/)
    command: "summarize-paper",

    // Note title prefix
    notePrefix: "AI Summary",

    // Tag added after summarization
    summaryTag: "summarized",

    // Skip if already tagged
    skipIfTagged: true,
};

async function runSummarizer() {
    const targetItem = item || (items && items[0]);

    if (!targetItem) {
        return "No item selected";
    }

    if (CONFIG.skipIfTagged) {
        const tags = targetItem.getTags();
        if (tags.some(t => t.tag === CONFIG.summaryTag)) {
            return "Item already summarized";
        }
    }

    const attachmentIDs = targetItem.getAttachments();
    if (!attachmentIDs || attachmentIDs.length === 0) {
        return "No attachments found";
    }

    let pdfPath = null;
    for (const attachmentID of attachmentIDs) {
        const attachment = await Zotero.Items.getAsync(attachmentID);
        if (attachment && attachment.attachmentContentType === "application/pdf") {
            pdfPath = await attachment.getFilePathAsync();
            break;
        }
    }

    if (!pdfPath) {
        return "No PDF attachment found";
    }

    const tempDir = Zotero.getTempDirectory().path;
    const outputFile = OS.Path.join(tempDir, `zotero_summary_${Date.now()}.txt`);

    const isWindows = Zotero.isWin;
    const pdfDir = pdfPath.substring(0, pdfPath.lastIndexOf(isWindows ? '\\' : '/'));

    let shell, shellArgs;
    if (isWindows) {
        shell = "cmd.exe";
        shellArgs = ["/c", `claude -p "/${CONFIG.command} ${pdfPath}" --output-format text --add-dir "${pdfDir}" > "${outputFile}"`];
    } else {
        shell = "/bin/sh";
        shellArgs = ["-c", `claude -p '/${CONFIG.command} ${pdfPath}' --output-format text --add-dir '${pdfDir}' > '${outputFile}'`];
    }

    try {
        await Zotero.Utilities.Internal.exec(shell, shellArgs);
        await Zotero.Promise.delay(1000);

        let summary;
        try {
            summary = await Zotero.File.getContentsAsync(outputFile);
        } catch (e) {
            const file = Components.classes["@mozilla.org/file/local;1"]
                .createInstance(Components.interfaces.nsIFile);
            file.initWithPath(outputFile);
            summary = Zotero.File.getContents(file);
        }

        if (!summary || !summary.trim()) {
            return "No summary generated - check that Claude CLI is installed";
        }

        const title = targetItem.getField("title") || "Untitled";
        const noteContent = `
<h1>${CONFIG.notePrefix}: ${title}</h1>
<hr/>
${summary.trim().replace(/\n/g, "<br/>")}
<hr/>
<p><em>Generated with /${CONFIG.command}</em></p>
        `.trim();

        const note = new Zotero.Item("note");
        note.setNote(noteContent);
        note.parentID = targetItem.id;
        note.libraryID = targetItem.libraryID;
        await note.saveTx();

        targetItem.addTag(CONFIG.summaryTag);
        await targetItem.saveTx();

        try { await OS.File.remove(outputFile); } catch (e) {}

        return `Summary created for: ${title}`;

    } catch (error) {
        return `Error: ${error.message || error}`;
    }
}

return await runSummarizer();
