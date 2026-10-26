// CachedState.qml - runtime view loaded from the disk cache.

import QtQuick

QtObject {
    property var authorFetchedAt: ({})
    property var authorsByThread: ({})
    property var doneThreadState: ({})
    property var messages: []
    property int pollIntervalMs: 0
    property real timestamp: 0
}
