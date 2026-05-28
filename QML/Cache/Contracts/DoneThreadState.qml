// DoneThreadState.qml - locally archived notification threads.

import QtQuick

QtObject {
    id: model

    property var threadIds: ({})

    function readFromObject(value) {
        threadIds = normalize(value)
    }

    function toObject() {
        return normalize(threadIds)
    }

    function normalize(value) {
        var result = {}

        if (!value)
            return result

        if (Array.isArray(value)) {
            for (var index = 0; index < value.length; index++) {
                var arrayId = String(value[index] || "").trim()
                if (arrayId)
                    result[arrayId] = true
            }
            return result
        }

        if (typeof value === "object") {
            for (var key in value) {
                if (value[key]) {
                    var objectId = String(key || "").trim()
                    if (objectId)
                        result[objectId] = true
                }
            }
        }

        return result
    }
}
