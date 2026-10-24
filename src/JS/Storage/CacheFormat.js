// CacheFormat.js - owns cache decoding, migration, and serialization.

// No QML singleton context is needed when these pure definitions are included in a worker.

// Bind the shared error contract before exposing pure cache-format operations.
function createFormat(errorContract) {
    // Return defaults for every field in the current cache format.
    function emptyPayload() {
        return {
            version: 0,
            lastFetched: 0,
            pollIntervalMs: 0,
            notifications: [],
            authorsByThread: {},
            authorFetchedAt: {},
            avatarMap: {},
            doneThreadState: {}
        };
    }

    // Read a current-format cache and run the done-state migration before exposure.
    function decodePayload(value, expectedVersion) {
        validatePayload(value, expectedVersion);
        var payload = emptyPayload();

        payload.version = value.version;
        payload.lastFetched = value.lastFetched || 0;
        payload.pollIntervalMs =
            Number.isInteger(value.pollIntervalMs) && value.pollIntervalMs > 0 ? value.pollIntervalMs : 0;
        payload.notifications = value.notifications || [];
        payload.authorsByThread = value.authorsByThread || {};
        payload.authorFetchedAt = value.authorFetchedAt || {};
        payload.avatarMap = value.avatarMap || {};
        payload.doneThreadState = normalizeDoneThreadState(value.doneThreadState);
        return payload;
    }

    // Reject corrupt or unsupported persisted data before the cache owner can overwrite it.
    function validatePayload(payload, expectedVersion) {
        // Reject damaged persisted data through the shared typed-error contract.
        function invalid(details) {
            throw errorContract.create("The saved cache could not be loaded.", details, false);
        }
        if (!payload || typeof payload !== "object" || Array.isArray(payload))
            invalid("The saved cache root must be an object.");
        if (
            !Number.isInteger(payload.version) ||
            payload.version < 1 ||
            (expectedVersion !== undefined && payload.version !== expectedVersion)
        )
            invalid("The saved cache has an unsupported format version.");
        if (!Number.isFinite(payload.lastFetched) || payload.lastFetched < 0)
            invalid("The saved cache has an invalid fetch timestamp.");
        if (!Array.isArray(payload.notifications)) invalid("The saved cache notifications are invalid.");
        for (let notification of payload.notifications)
            if (
                !notification ||
                typeof notification !== "object" ||
                Array.isArray(notification) ||
                typeof notification.threadId !== "string" ||
                !notification.threadId
            )
                invalid("The saved cache contains an invalid notification record.");
        for (let name of ["authorsByThread", "authorFetchedAt", "avatarMap", "doneThreadState"]) {
            let value = payload[name];
            // Legacy Done lists are migrated below, before any runtime component receives them.
            if (name === "doneThreadState" && Array.isArray(value)) continue;
            if (!value || typeof value !== "object" || Array.isArray(value))
                invalid("The saved cache field " + name + " is invalid.");
        }
        for (let login of Object.keys(payload.avatarMap)) {
            if (!/^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9])?(?:\[bot\])?$/.test(login))
                invalid("The saved cache contains an invalid avatar login.");
            let entry = payload.avatarMap[login];
            if (
                !entry ||
                typeof entry !== "object" ||
                Array.isArray(entry) ||
                (entry.localFile && !isAvatarFileName(entry.localFile))
            )
                invalid("The saved cache contains an invalid avatar filename.");
        }
    }

    // Keep filename validation identical in persisted-data checks and local URL resolution.
    function isAvatarFileName(value) {
        return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*(?:\[bot\])?\.png$/.test(value);
    }

    // Convert supported legacy done-state shapes into the current map format.
    function normalizeDoneThreadState(value) {
        var result = {};
        if (!value) return result;

        if (Array.isArray(value)) {
            for (var index = 0; index < value.length; index++) {
                var arrayId = String(value[index] || "").trim();
                if (arrayId) result[arrayId] = { source: "local", updatedAt: "", savedAt: 0 };
            }
            return result;
        }

        if (typeof value !== "object") return result;
        for (var key in value) {
            var threadId = String(key || "").trim();
            var entry = value[key];
            if (!threadId || !entry || typeof entry !== "object" || Array.isArray(entry)) continue;
            result[threadId] = {
                source: String(entry.source || "local"),
                updatedAt: String(entry.updatedAt || ""),
                savedAt: entry.savedAt || 0
            };
        }
        return result;
    }

    // Resolve an avatar cache record to the URL used by QML images.
    function avatarLocalUrl(value, cacheDir, avatarSubdirectory) {
        var entry = value || {};
        if (!cacheDir || !avatarSubdirectory) return "";
        var prefix = "file://" + cacheDir + "/" + avatarSubdirectory + "/";
        var localFile = String(entry.localFile || "");
        if (!localFile) {
            var localUrl = String(entry.localUrl || "");
            if (localUrl.indexOf(prefix) !== 0) return "";
            localFile = localUrl.substring(prefix.length);
        }
        // A persisted filename is one avatar basename, never a path or encoded URL component.
        if (!isAvatarFileName(localFile)) return "";
        return prefix + localFile;
    }

    // Build a plain object containing only current-format cache fields.
    function serializePayload(value) {
        return {
            version: value.version,
            lastFetched: value.lastFetched,
            pollIntervalMs: value.pollIntervalMs || 0,
            notifications: value.notifications || [],
            authorsByThread: value.authorsByThread || {},
            authorFetchedAt: value.authorFetchedAt || {},
            avatarMap: value.avatarMap || {},
            doneThreadState: normalizeDoneThreadState(value.doneThreadState)
        };
    }

    return {
        emptyPayload,
        decodePayload,
        normalizeDoneThreadState,
        avatarLocalUrl,
        serializePayload,
        validatePayload,
        isAvatarFileName
    };
}
