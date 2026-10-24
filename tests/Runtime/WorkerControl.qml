// WorkerControl.qml - distinguishes Qt's own multi-worker diagnostics from plugin warnings.

import QtQuick
import Quickshell

ShellRoot {
    id: root

    property int replies: 0

    Component.onCompleted: {
        first.sendMessage({});
        second.sendMessage({});
    }
    onRepliesChanged: {
        if (replies === 2) {
            console.info("WORKER_CONTROL_PASSED");
            finish.start();
        }
    }

    WorkerScript {
        id: first

        source: "Echo.js"

        onMessage: root.replies++
    }
    WorkerScript {
        id: second

        source: "Echo.js"

        onMessage: root.replies++
    }
    Timer {
        id: finish

        interval: 50

        onTriggered: Qt.exit(0)
    }
    Timer {
        interval: 5000
        running: true

        onTriggered: Qt.exit(1)
    }
}
