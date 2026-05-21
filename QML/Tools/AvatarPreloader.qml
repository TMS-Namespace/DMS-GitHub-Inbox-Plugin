// AvatarPreloader.qml - Manages QML Image preload cache for avatars
//
// Maintains a map of avatar URLs and a Repeater of hidden Image elements
// that warm QML's image provider. Provides methods to queue avatars from
// inbox message owners and author lists.

import QtQuick
import ".."

Item {
    id: preloader
    visible: false
    width: 0
    height: 0

    // -- State ----------------------------------------------------------------
    property var entries: []         // Array of { key, source }
    property var entryMap: ({})      // key -> source (dedup)
    property int limit: GitHubConstants.avatarPreloadTotalCacheLimit

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] AvatarPreloader: " + label)
    }

    function queueFromAuthors(authors) {
        _perfLog("queueFromAuthors — input=" + (authors ? authors.length : 0) + " existing=" + entries.length)
        if (limit <= 0 || !authors || authors.length === 0 || entries.length >= limit)
            return

        var nextEntries = entries.slice(0)
        var nextMap = _cloneMap(entryMap)
        var changed = false

        for (var index = 0; index < authors.length; index++) {
            if (nextEntries.length >= limit)
                break

            var author = authors[index]
            var login = String((author && author.login) || "").trim()
            var avatarUrl = AuthorUtils.authorAvatarUrl(author)
            var key = AuthorUtils.authorKey(login, (author && author.htmlUrl) || "", avatarUrl)
            if (String(avatarUrl || "").indexOf("file://") === 0)
                continue
            if (!key || !avatarUrl || nextMap.hasOwnProperty(key))
                continue

            nextMap[key] = avatarUrl
            nextEntries.push({ key: key, source: avatarUrl })
            changed = true
        }

        if (changed) {
            entryMap = nextMap
            entries = nextEntries
            _perfLog("queueFromAuthors — done, entries now=" + nextEntries.length)
        }
    }

    function queueFromMessages(items) {
        if (limit <= 0 || !items || items.length === 0)
            return

        var ownerAuthors = []
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            ownerAuthors.push({
                login: item.repositoryOwnerLogin || "",
                avatarUrl: item.repositoryOwnerAvatarUrl || "",
                htmlUrl: item.repositoryOwnerLogin
                    ? (GitHubConstants.githubWebBaseUrl + "/" + encodeURIComponent(item.repositoryOwnerLogin))
                    : ""
            })
        }

        queueFromAuthors(ownerAuthors)
    }

    /// Update entry source URL for a given login (e.g. when avatar is cached locally).
    function updateEntrySource(login, newSource) {
        var nextEntries = entries.slice(0)
        var changed = false
        for (var i = 0; i < nextEntries.length; i++) {
            if (nextEntries[i].key === login && nextEntries[i].source !== newSource) {
                nextEntries[i] = { key: login, source: newSource }
                changed = true
            }
        }
        if (changed)
            entries = nextEntries
    }

    function reset() {
        entries = []
        entryMap = ({})
    }

    // =========================================================================
    //  HIDDEN IMAGE REPEATER
    // =========================================================================

    Repeater {
        model: preloader.entries

        delegate: Image {
            required property var modelData
            source: modelData.source || ""
            asynchronous: true
            cache: true
            sourceSize.width: GitHubConstants.avatarPreloadSourceSizePx
            sourceSize.height: GitHubConstants.avatarPreloadSourceSizePx
            visible: false
        }
    }

    // =========================================================================
    //  INTERNAL
    // =========================================================================

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
    }
}
