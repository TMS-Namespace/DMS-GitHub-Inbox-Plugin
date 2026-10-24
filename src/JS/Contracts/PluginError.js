// PluginError.js - one serializable error contract for QML libraries and worker modules.

// Pure definitions also run through Qt.include in worker contexts; they own no shared mutable state.

// Keep errors plain so WorkerScript can transfer them without losing their fields.
function create(userMessage, details, retryable) {
    return {
        name: "PluginError",
        userMessage: String(userMessage || "The operation failed."),
        details: String(details || ""),
        retryable: retryable === true
    };
}

// Recognize only errors that carry the complete public and diagnostic contract.
function isPluginError(value) {
    return (
        !!value &&
        value.name === "PluginError" &&
        typeof value.userMessage === "string" &&
        typeof value.details === "string" &&
        typeof value.retryable === "boolean"
    );
}

// Convert native JSON/worker exceptions at the boundary while retaining private diagnostics.
function fromException(error, userMessage) {
    return isPluginError(error)
        ? error
        : create(userMessage, String((error && error.message) || error || "Unknown error"), false);
}
