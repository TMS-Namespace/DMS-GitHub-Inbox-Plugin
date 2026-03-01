// Settings.qml - Settings page for GitHub Inbox plugin

import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "github-inbox"

    property string tokenValue: ""
    property bool showToken: false
    property int groupLimitValue: 25
    property int fetchPagesValue: 3
    property int popupHeightValue: 10

    function saveValue(key, value) {
        if (pluginService)
            pluginService.savePluginData(root.pluginId, key, value)
    }

    function loadValue(key, defaultValue) {
        if (pluginService)
            return pluginService.loadPluginData(root.pluginId, key, defaultValue)
        return defaultValue
    }

    function loadToken() {
        tokenValue = loadValue("githubToken", "")
    }

    function clampGroupLimit(value) {
        var limit = parseInt(value || "25")
        if (isNaN(limit))
            return 25
        return Math.max(1, Math.min(25, limit))
    }

    function loadGroupLimit() {
        groupLimitValue = clampGroupLimit(loadValue("groupItemLimit", "25"))
    }

    function clampFetchPages(value) {
        var pages = parseInt(value || "3")
        if (isNaN(pages))
            return 3
        return Math.max(1, Math.min(10, pages))
    }

    function loadFetchPages() {
        fetchPagesValue = clampFetchPages(loadValue("fetchPages", "3"))
    }

    function clampPopupHeight(value) {
        var units = parseInt(value || "10")
        if (isNaN(units))
            return 10
        return Math.max(5, Math.min(40, units))
    }

    function loadPopupHeight() {
        popupHeightValue = clampPopupHeight(loadValue("popupHeight", "10"))
    }
    onPluginServiceChanged: {
        if (pluginService) {
            loadToken()
            loadGroupLimit()
            loadFetchPages()
            loadPopupHeight()
        }
    }

    Component.onCompleted: {
        loadToken()
        loadGroupLimit()
        loadFetchPages()
        loadPopupHeight()
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "GitHub Inbox"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        width: parent.width
        text: "Show GitHub notifications directly in DankBar and a popup list.\nUse a GitHub classic personal access token with the 'notifications' scope."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        width: githubRow.width
        height: githubRow.height

        Row {
            id: githubRow
            spacing: Theme.spacingXS

            DankIcon {
                name: "link"
                size: Theme.fontSizeSmall
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                opacity: tokenLinkArea.containsMouse ? 1.0 : 0.7
            }

            StyledText {
                text: "Create classic token on GitHub"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                opacity: tokenLinkArea.containsMouse ? 1.0 : 0.7
            }
        }

        MouseArea {
            id: tokenLinkArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("https://github.com/settings/tokens")
        }
    }

    Item {
        width: parent.width
        height: 72

        Column {
            anchors.fill: parent
            spacing: Theme.spacingXS

            StyledText {
                text: "GitHub Classic Token"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                font.weight: Font.Medium
            }

            Rectangle {
                id: tokenField
                width: parent.width
                height: 42
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: tokenInput.activeFocus ? Theme.primary : Theme.outlineVariant

                TextInput {
                    id: tokenInput
                    anchors.left: parent.left
                    anchors.right: visibilityButton.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    text: root.tokenValue
                    echoMode: root.showToken ? TextInput.Normal : TextInput.Password
                    selectByMouse: true

                    onTextChanged: {
                        if (text !== root.tokenValue)
                            root.tokenValue = text
                    }

                    onTextEdited: root.saveValue("githubToken", text)
                }

                StyledText {
                    visible: tokenInput.text.length === 0 && !tokenInput.activeFocus
                    text: "ghp_..."
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.left: tokenInput.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: visibilityButton
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: visibilityArea.containsMouse
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                           : "transparent"

                    MouseArea {
                        id: visibilityArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showToken = !root.showToken
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.showToken ? "visibility_off" : "visibility"
                        size: 18
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Refresh Interval"
        description: "How often the widget checks GitHub notifications"
        options: [
            { label: "1 minute", value: "60" },
            { label: "2 minutes", value: "120" },
            { label: "5 minutes", value: "300" },
            { label: "10 minutes", value: "600" },
            { label: "15 minutes", value: "900" }
        ]
        defaultValue: "120"
    }

    ToggleSetting {
        settingKey: "loadAuthorInfo"
        label: "Load Author Details"
        description: "Load author avatars and profile names for each notification"
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "Note: This will considerably increase notification loading time."
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        width: parent.width
        height: 52

        Column {
            anchors.fill: parent
            spacing: 4

            Row {
                width: parent.width

                StyledText {
                    text: "Max Items Per Group"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: groupSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: 24

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (groupSlider.value - 1) / 24 * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: groupHandle
                    width: 18
                    height: 18
                    radius: 9
                    color: groupMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: 2
                    x: (groupSlider.value - 1) / 24 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: groupSlider
                    property real value: root.groupLimitValue
                }

                MouseArea {
                    id: groupMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        groupSlider.value = Math.round(1 + ratio * 24)
                    }

                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                    onReleased: {
                        var limited = root.clampGroupLimit(groupSlider.value)
                        groupSlider.value = limited
                        root.groupLimitValue = limited
                        root.saveValue("groupItemLimit", String(limited))
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 52

        Column {
            anchors.fill: parent
            spacing: 4

            Row {
                width: parent.width

                StyledText {
                    text: "Max Pages to Fetch"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: fetchPagesSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: 24

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (fetchPagesSlider.value - 1) / 9 * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: fetchPagesHandle
                    width: 18
                    height: 18
                    radius: 9
                    color: fetchPagesMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: 2
                    x: (fetchPagesSlider.value - 1) / 9 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: fetchPagesSlider
                    property real value: root.fetchPagesValue
                }

                MouseArea {
                    id: fetchPagesMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        fetchPagesSlider.value = Math.round(1 + ratio * 9)
                    }

                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                    onReleased: {
                        var limited = root.clampFetchPages(fetchPagesSlider.value)
                        fetchPagesSlider.value = limited
                        root.fetchPagesValue = limited
                        root.saveValue("fetchPages", String(limited))
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 52

        Column {
            anchors.fill: parent
            spacing: 4

            Row {
                width: parent.width

                StyledText {
                    text: "Popup Height"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: popupHeightSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: 24

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (popupHeightSlider.value - 5) / 35 * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: popupHeightHandle
                    width: 18
                    height: 18
                    radius: 9
                    color: popupHeightMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: 2
                    x: (popupHeightSlider.value - 5) / 35 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: popupHeightSlider
                    property real value: root.popupHeightValue
                }

                MouseArea {
                    id: popupHeightMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        popupHeightSlider.value = Math.round(5 + ratio * 35)
                    }

                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                    onReleased: {
                        var limited = root.clampPopupHeight(popupHeightSlider.value)
                        popupHeightSlider.value = limited
                        root.popupHeightValue = limited
                        root.saveValue("popupHeight", String(limited))
                    }
                }
            }
        }
    }

    SelectionSetting {
        settingKey: "titleLines"
        label: "Max Rows for Title"
        description: "How many lines each notification title can use"
        options: [
            { label: "1 line", value: "1" },
            { label: "2 lines", value: "2" },
            { label: "3 lines", value: "3" },
            { label: "4 lines", value: "4" }
        ]
        defaultValue: "2"
    }
}
