// PluginComponent.qml - stand-in for the host's widget plugin root contract.

import QtQuick

Item {
    property var horizontalBarPill: null
    property int iconSize: 24
    property string layerNamespacePlugin: ""
    property var pluginData: ({})
    property var pluginService: null
    property var popoutContent: null
    property real popoutHeight: 720
    property real popoutWidth: 640
    property int textSize: 14
    property var verticalBarPill: null

    signal _popoutClosed

    function closePopout() {
        _popoutClosed();
    }
}
