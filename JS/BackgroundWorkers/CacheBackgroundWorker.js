// CacheBackgroundWorker.js - background JSON parse/stringify for the disk cache.

WorkerScript.onMessage = function (message) {
    if (!message || !message.action) {
        console.error('Invalid message received:', message);
        return;
    }
    var action = message.action || ""

    if (action === "parseCache") {
        var data
        try {
            data = JSON.parse(message.text || "{}")
        } catch (error) {
            data = {}
        }

        WorkerScript.sendMessage({
            action: "cacheParsed",
            seq: message.seq || 0,
            data: data || {}
        })
        return
    }

    if (action === "stringifyCache") {
        var text = "{}"
        try {
            text = JSON.stringify(message.payload || {})
        } catch (error) {
            text = "{}"
        }

        WorkerScript.sendMessage({
            action: "cacheStringified",
            seq: message.seq || 0,
            text: text
        })
    }
}
