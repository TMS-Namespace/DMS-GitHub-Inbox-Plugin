// DScrollbar.qml - uses the real Qt attached API instead of synthesizing thumb calculations.
import QtQuick
import QtQuick.Controls as Controls

Controls.ScrollBar {
    property bool allowed: true
    property Flickable targetFlickable: null

    policy: allowed && targetFlickable && targetFlickable.contentHeight > targetFlickable.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
}
