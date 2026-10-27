// AvatarDownloadWorker.qml - one built-in Dux download with bounded provider-policy retries.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
    id: worker

    property int attempts: 0
    property bool autoStart: true
    property bool completed: false
    property var downloadCommand: []
    property int maximumRetries: 0
    property int retryDelayMs: 0
    property int retryWindowMs: 0
    property real startedAtMs: 0

    signal finished(bool success)

    // Retry only within both the attempt limit and the allowed retry-start window.
    function handleExit(exitCode) {
        if (completed)
            return;
        if (exitCode !== 0 && attempts <= maximumRetries && Date.now() + retryDelayMs < startedAtMs + retryWindowMs) {
            retryTimer.restart();
            return;
        }
        completed = true;
        finished(exitCode === 0);
    }
    // Relaunch the same validated argument array without a shell or interpolated values.
    function startAttempt() {
        if (completed)
            return;
        if (attempts === 0)
            startedAtMs = Date.now();
        attempts++;
        download.running = true;
    }

    visible: false

    Component.onCompleted: {
        if (autoStart)
            startAttempt();
    }

    Process {
        id: download

        command: worker.downloadCommand

        stderr: SplitParser {
            onRead: function (line) {}
        }
        stdout: SplitParser {
            onRead: function (line) {}
        }

        onExited: exitCode => worker.handleExit(exitCode)
    }
    Timer {
        id: retryTimer

        interval: worker.retryDelayMs

        onTriggered: {
            if (Date.now() < worker.startedAtMs + worker.retryWindowMs)
                worker.startAttempt();
            else {
                worker.completed = true;
                worker.finished(false);
            }
        }
    }
}
