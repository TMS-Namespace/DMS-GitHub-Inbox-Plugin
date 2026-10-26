// SettingsCacheView.qml - collapsed-by-default cache maintenance using native Dux settings controls.

pragma ComponentBehavior: Bound

import QtQuick
import qs.DCommon.Widgets

DCollapsibleSection {
    id: cacheView

    signal clearCacheRequested

    description: "Inbox messages, author details, and avatars are cached locally for faster loading."
    objectName: "cacheSettingsSection"
    title: "Cache"
    width: parent.width

    DButton {
        maximumWidth: cacheView.width
        objectName: "clearCacheButton"
        text: "Clear Cache"

        onClicked: cacheView.clearCacheRequested()
    }
}
