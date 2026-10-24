// CacheBackgroundWorker.js - transfers validated current-format data and typed failures across the worker boundary.

// Include stateless libraries in this worker context; QML uses their normal module imports.
Qt.include("../Contracts/PluginError.js");
var PluginError = { create: create, isPluginError: isPluginError, fromException: fromException };
Qt.include("../Storage/CacheFormat.js");
var CacheFormat = createFormat(PluginError);

// WorkerScript cannot transfer native exceptions; transport the serializable error contract instead.
WorkerScript.onMessage = function (message) {
    let action = (message && message.action) || "unknown";
    try {
        if (action === "parseCache") {
            let data = CacheFormat.decodePayload(JSON.parse(message.text), message.expectedVersion);
            WorkerScript.sendMessage({ action: "cacheParsed", seq: message.seq || 0, data: data });
        } else if (action === "stringifyCache") {
            let payload = CacheFormat.serializePayload(message.payload);
            CacheFormat.validatePayload(payload);
            WorkerScript.sendMessage({
                action: "cacheStringified",
                seq: message.seq || 0,
                text: JSON.stringify(payload)
            });
        } else {
            throw PluginError.create("Cache processing failed.", "Invalid cache worker request", false);
        }
    } catch (error) {
        let failure = PluginError.fromException(
            error,
            action === "parseCache"
                ? "The saved cache could not be loaded."
                : "The current cache state could not be saved."
        );
        WorkerScript.sendMessage({
            action: "cacheError",
            seq: (message && message.seq) || 0,
            operation: action,
            error: failure.userMessage,
            failure: failure
        });
    }
};
