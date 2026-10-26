// CacheSerialization.js - QML adapter for the pure cache format used by background workers.

.pragma library
.import "CacheFormat.js" as CacheFormat
.import "../Contracts/PluginError.js" as PluginError

var _format = CacheFormat.createFormat(PluginError);

// Delegate to the canonical storage-format implementation.
function emptyPayload() {
    return _format.emptyPayload();
}

// Delegate to the canonical storage-format implementation.
function decodePayload(value, expectedVersion) {
    return _format.decodePayload(value, expectedVersion);
}

// Delegate to the canonical storage-format implementation.
function normalizeDoneThreadState(value) {
    return _format.normalizeDoneThreadState(value);
}

// Delegate to the canonical storage-format implementation.
function avatarLocalUrl(value, cacheDir, avatarSubdirectory) {
    return _format.avatarLocalUrl(value, cacheDir, avatarSubdirectory);
}

// Delegate to the canonical storage-format implementation.
function serializePayload(value) {
    return _format.serializePayload(value);
}
