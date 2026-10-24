// FileView.qml - headless stand-in for the installed Quickshell.Io FileView API.

import QtQuick

QtObject {
    property bool atomicWrites: false
    property bool blockLoading: false
    property string path: ""
    property bool preload: false

    signal loadFailed(var error)
    signal saveFailed(var error)

    function setText(text) {
    }
    function text() {
        return "";
    }
}
