// CacheSerialization.js - QML adapter for the pure cache format used by background workers.

.pragma library
.import "CacheFormat.js" as CacheFormat
.import "../Contracts/PluginError.js" as PluginError

var _format = CacheFormat.createFormat(PluginError);

// Return a fresh payload with defaults for every persisted cache field.
function emptyPayload() {
    return _format.emptyPayload();
}

// Validate and migrate persisted data through the shared cache-format decoder.
function decodePayload(value, expectedVersion) {
    return _format.decodePayload(value, expectedVersion);
}

// Convert supported Done-state records into the current thread-keyed map.
function normalizeDoneThreadState(value) {
    return _format.normalizeDoneThreadState(value);
}

// Resolve an avatar record to a local URL through the shared filename checks.
function avatarLocalUrl(value, cacheDir, avatarSubdirectory) {
    return _format.avatarLocalUrl(value, cacheDir, avatarSubdirectory);
}

// Serialize only the fields declared by the current cache format.
function serializePayload(value) {
    return _format.serializePayload(value);
}
