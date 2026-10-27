// AvatarPreloader.qml - Manages QML Image preload cache for avatars
//
// Maintains a map of avatar URLs and a Repeater of hidden Image elements
// that warm QML's image provider. Provides methods to queue avatars from
// inbox message owners and author lists.

import QtQuick
import ".."

Item {
    id: preloader

    // -- State ----------------------------------------------------------------
    property var entries: []         // Array of { key, source }
    property var entryMap: ({})      // key -> source (dedup)
    property int limit: GitHubConstants.avatarPreloadTotalCacheLimit

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    // Replace map identity so QML bindings can observe an update.
    function _cloneMap(source) {
        let copy = {};
        for (let key in source)
            copy[key] = source[key];
        return copy;
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        PluginLogger.debug("AvatarPreloader", label);
    }
    // Warm only bounded, deduplicated local images after author metadata changes.
    function queueFromAuthors(authors) {
        _perfLog("queueFromAuthors --- input=" + (authors ? authors.length : 0) + " existing=" + entries.length);
        if (limit <= 0 || !authors || authors.length === 0 || entries.length >= limit)
            return;
        let nextEntries = entries.slice(0);
        let nextMap = _cloneMap(entryMap);
        let changed = false;

        for (let index = 0; index < authors.length; index++) {
            if (nextEntries.length >= limit)
                break;
            let author = authors[index];
            let login = String((author && author.login) || "").trim();
            let avatarUrl = AuthorUtils.authorAvatarUrl(author);
            let key = AuthorUtils.authorKey(login, (author && author.htmlUrl) || "", avatarUrl);
            if (String(avatarUrl || "").indexOf("file://") === 0)
                continue;
            if (!key || !avatarUrl || nextMap.hasOwnProperty(key))
                continue;
            nextMap[key] = avatarUrl;
            nextEntries.push({
                key: key,
                source: avatarUrl
            });
            changed = true;
        }

        if (changed) {
            entryMap = nextMap;
            entries = nextEntries;
            _perfLog("queueFromAuthors --- done, entries now=" + nextEntries.length);
        }
    }
    // Warm repository resources through the same bounded preloader.
    function queueFromMessages(items) {
        if (limit <= 0 || !items || items.length === 0)
            return;
        let ownerAuthors = [];
        for (let index = 0; index < items.length; index++) {
            let item = items[index];
            ownerAuthors.push({
                login: item.repositoryOwnerLogin || "",
                avatarUrl: item.repositoryOwnerAvatarUrl || "",
                htmlUrl: item.repositoryOwnerLogin ? (GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(item.repositoryOwnerLogin)) : ""
            });
        }

        queueFromAuthors(ownerAuthors);
    }
    // Release hidden preload images and clear their deduplication map.
    function reset() {
        entries = [];
        entryMap = ({});
    }

    /// Update entry source URL for a given login (e.g. when avatar is cached locally).
    function updateEntrySource(login, newSource) {
        let nextEntries = entries.slice(0);
        let changed = false;
        for (let i = 0; i < nextEntries.length; i++) {
            if (nextEntries[i].key === login && nextEntries[i].source !== newSource) {
                nextEntries[i] = {
                    key: login,
                    source: newSource
                };
                changed = true;
            }
        }
        if (changed)
            entries = nextEntries;
    }

    height: 0
    visible: false
    width: 0

    // =========================================================================
    //  HIDDEN IMAGE REPEATER
    // =========================================================================

    Repeater {
        model: preloader.entries

        delegate: Image {
            required property var modelData

            asynchronous: true
            cache: true
            source: modelData.source || ""
            sourceSize.height: GitHubConstants.avatarPreloadSourceSizePx
            sourceSize.width: GitHubConstants.avatarPreloadSourceSizePx
            visible: false
        }
    }
}
