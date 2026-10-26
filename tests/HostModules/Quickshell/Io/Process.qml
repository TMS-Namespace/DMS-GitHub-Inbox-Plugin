// Process.qml - headless stand-in for Quickshell.Io Process in unit tests.

import QtQuick

QtObject {
    property var arguments: []
    property string command: ""
    property bool running: false
    property var stderr: null
    property bool stdinEnabled: false
    property var stdout: null

    signal exited(int exitCode, int exitStatus)
    signal started

    function start() {
        running = true;
    }
    function write(value) {
    }
}
