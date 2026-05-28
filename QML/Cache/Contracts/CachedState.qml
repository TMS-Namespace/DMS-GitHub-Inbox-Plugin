// CachedState.qml - runtime view loaded from the disk cache.

import QtQuick

QtObject {
    id: model

    property var messages: []
    property var authorsByThread: ({})
    property var authorFetchedAt: ({})
    property var doneThreadState: ({})
    property real timestamp: 0

    function readFromObject(value) {
        var source = value || ({})
        messages = source.messages || []
        authorsByThread = source.authorsByThread || ({})
        authorFetchedAt = source.authorFetchedAt || ({})
        doneThreadState = source.doneThreadState || ({})
        timestamp = source.timestamp || 0
    }

    function toObject() {
        return {
            messages: messages || [],
            authorsByThread: authorsByThread || ({}),
            authorFetchedAt: authorFetchedAt || ({}),
            doneThreadState: doneThreadState || ({}),
            timestamp: timestamp || 0
        }
    }
}
