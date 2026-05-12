// CachePayload.qml - serialized JSON cache contract.

import QtQuick

QtObject {
    id: model

    property int version: 0
    property real lastFetched: 0
    property var notifications: []
    property var authorsByThread: ({})
    property var authorFetchedAt: ({})
    property var avatarMap: ({})

    function readFromObject(value, expectedVersion) {
        var source = value || ({})
        if ((source.version || 0) !== expectedVersion)
            source = ({})

        version = source.version || 0
        lastFetched = source.lastFetched || 0
        notifications = source.notifications || []
        authorsByThread = source.authorsByThread || ({})
        authorFetchedAt = source.authorFetchedAt || ({})
        avatarMap = source.avatarMap || ({})
    }

    function toObject() {
        return {
            version: version,
            lastFetched: lastFetched,
            notifications: notifications || [],
            authorsByThread: authorsByThread || ({}),
            authorFetchedAt: authorFetchedAt || ({}),
            avatarMap: avatarMap || ({})
        }
    }
}
