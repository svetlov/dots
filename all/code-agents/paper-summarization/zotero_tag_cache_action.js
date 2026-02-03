/*
 * Zotero Actions & Tags - Tag Cache Builder
 * Intended to be invoked on main window open.
 */

var CONFIG = {
    // Absolute path override (set to null to use default location)
    // Windows example: C:\\Users\\<user>\\AppData\\Roaming\\Zotero\\tags.txt
    cachePath: null,
    // Apply tags.remap.json if present next to tags.txt
    applyRemap: true,
    // Remove old tags after applying remap
    removeOldTags: true,
    // Exclude attachments to reduce work
    excludeAttachments: true
};

async function buildTagCache() {
    var libraryID = null;
    try {
        if (typeof ZoteroPane !== "undefined" && ZoteroPane.getSelectedLibraryID) {
            libraryID = ZoteroPane.getSelectedLibraryID();
        }
    } catch (e) {}
    if (!libraryID) {
        libraryID = Zotero.Libraries.userLibraryID;
    }

    var cachePath = CONFIG.cachePath;
    if (!cachePath) {
        var appData = null;
        try {
            appData = (Zotero.getEnv && Zotero.getEnv("APPDATA")) || null;
        } catch (e) {}
        if (!appData) {
            try {
                var userProfile = (Zotero.getEnv && Zotero.getEnv("USERPROFILE")) || null;
                if (userProfile) {
                    appData = PathUtils.join(userProfile, "AppData", "Roaming");
                }
            } catch (e) {}
        }
        if (appData) {
            cachePath = PathUtils.join(appData, "Zotero", "tags.txt");
        } else if (Zotero.Profile && Zotero.Profile.dir) {
            cachePath = PathUtils.join(Zotero.Profile.dir, "tags.txt");
        } else if (typeof PathUtils !== "undefined" && PathUtils.profileDir) {
            cachePath = PathUtils.join(PathUtils.profileDir, "tags.txt");
        } else {
            cachePath = PathUtils.join(PathUtils.tempDir, "tags.txt");
        }
    }

    var s = new Zotero.Search();
    s.libraryID = libraryID;
    if (CONFIG.excludeAttachments) {
        s.addCondition("itemType", "isNot", "attachment");
    }
    var itemIDs = await s.search();

    var tagSet = new Set();
    var batchSize = 500;
    for (var i = 0; i < itemIDs.length; i += batchSize) {
        var batchIDs = itemIDs.slice(i, i + batchSize);
        var items = await Zotero.Items.getAsync(batchIDs);
        for (var j = 0; j < items.length; j++) {
            var tags = items[j].getTags();
            for (var k = 0; k < tags.length; k++) {
                if (tags[k] && tags[k].tag) {
                    tagSet.add(tags[k].tag);
                }
            }
        }
    }

    var tagList = Array.from(tagSet).sort().join("\n");
    await Zotero.File.putContentsAsync(cachePath, tagList);

    // Optional: apply tags.remap.json next to tags.txt
    if (CONFIG.applyRemap) {
        var remapPath = cachePath.replace(/tags\.txt$/i, "tags.remap.json");
        var remapRaw = "";
        try {
            remapRaw = await Zotero.File.getContentsAsync(remapPath);
        } catch (e) {}
        if (remapRaw && remapRaw.trim()) {
            var remap = null;
            try { remap = JSON.parse(remapRaw); } catch (e) { remap = null; }
            if (remap && typeof remap === "object") {
                for (var j = 0; j < itemIDs.length; j += batchSize) {
                    var batchIDsRemap = itemIDs.slice(j, j + batchSize);
                    var itemsRemap = await Zotero.Items.getAsync(batchIDsRemap);
                    for (var k = 0; k < itemsRemap.length; k++) {
                        var tags = itemsRemap[k].getTags();
                        if (!tags || !tags.length) continue;
                        var tagNames = tags.map(function(t) { return t.tag; });
                        var changed = false;
                        for (var t = 0; t < tagNames.length; t++) {
                            var oldTag = tagNames[t];
                            var newTags = remap[oldTag];
                            if (!newTags || !newTags.length) continue;
                            for (var n = 0; n < newTags.length; n++) {
                                var newTag = newTags[n];
                                if (newTag && tagNames.indexOf(newTag) === -1) {
                                    itemsRemap[k].addTag(newTag);
                                    tagNames.push(newTag);
                                    changed = true;
                                }
                            }
                            if (CONFIG.removeOldTags) {
                                itemsRemap[k].removeTag(oldTag);
                                changed = true;
                            }
                        }
                        if (changed) {
                            await itemsRemap[k].saveTx();
                        }
                    }
                }
            }
        }
    }

    // Optional: remove tags listed in tags.remove.txt next to tags.txt
    var removePath = cachePath.replace(/tags\.txt$/i, "tags.remove.txt");
    var removeListRaw = "";
    try {
        removeListRaw = await Zotero.File.getContentsAsync(removePath);
    } catch (e) {}
    var removedCount = 0;
    if (removeListRaw && removeListRaw.trim()) {
        var toRemoveSet = new Set();
        var lines = removeListRaw.split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line || line.indexOf("#") === 0) continue;
            toRemoveSet.add(line);
        }
        if (toRemoveSet.size) {
            var removeTags = Array.from(toRemoveSet);
            for (var r = 0; r < removeTags.length; r++) {
                var tagName = removeTags[r];
                for (var j = 0; j < itemIDs.length; j += batchSize) {
                    var batchIDs2 = itemIDs.slice(j, j + batchSize);
                    var items2 = await Zotero.Items.getAsync(batchIDs2);
                    for (var k = 0; k < items2.length; k++) {
                        var tags2 = items2[k].getTags();
                        var hasTag = false;
                        for (var t = 0; t < tags2.length; t++) {
                            if (tags2[t] && tags2[t].tag === tagName) {
                                hasTag = true;
                                break;
                            }
                        }
                        if (hasTag) {
                            await items2[k].removeTag(tagName);
                            await items2[k].saveTx();
                            removedCount++;
                        }
                    }
                }
            }
        }
    }

    return "Tag cache updated: " + cachePath + " (" + tagSet.size + " tags)" +
        (removedCount ? (", removed " + removedCount + " item tag entries") : "");
}

return await buildTagCache();
