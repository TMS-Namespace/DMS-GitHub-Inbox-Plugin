// CachePayload.qml - serialized JSON cache contract.

import QtQuick

QtObject {
    property var authorFetchedAt: ({})
    property var authorsByThread: ({})
    property var avatarMap: ({})
    property var doneThreadState: ({})
    property real lastFetched: 0
    property var notifications: []
    property int pollIntervalMs: 0
    property int version: 0
}
