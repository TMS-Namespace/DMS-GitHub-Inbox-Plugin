// Settings.qml - Settings page for GitHub Inbox plugin

import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import ".."

PluginSettings {
    id: root
    pluginId: GitHubConstants.pluginNamespaceId

    property string tokenValue: ""
    property bool showToken: false
    property int groupLimitValue: GitHubConstants.defaultGroupItemLimit
    property int fetchPagesValue: GitHubConstants.defaultFetchPageCount
    property int popupHeightValue: GitHubConstants.defaultPopupHeightUnits
    property int cacheTtlValue: GitHubConstants.defaultCacheTtlMinutes
    property string tokenStatusMessage: ""
    property bool tokenSaveFailed: false

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
        secretStore.loadToken()
    }

    function persistToken(value) {
        var trimmed = String(value || "").trim()
        tokenValue = trimmed
        tokenSaveFailed = false
        tokenStatusMessage = trimmed ? "Saving token to Secret Service..." : "Removing token from Secret Service..."
        if (trimmed)
            secretStore.storeToken(trimmed, false)
        else
            secretStore.clearToken()
    }

    function clampGroupLimit(value) {
        var limit = parseInt(value || GitHubConstants.defaultGroupItemLimit)
        if (isNaN(limit))
            return GitHubConstants.defaultGroupItemLimit
        return Math.max(GitHubConstants.minGroupItemLimit, Math.min(GitHubConstants.maxGroupItemLimit, limit))
    }

    function loadGroupLimit() {
        groupLimitValue = clampGroupLimit(loadValue("groupItemLimit", GitHubConstants.defaultGroupItemLimit))
    }

    function clampFetchPages(value) {
        var pages = parseInt(value || GitHubConstants.defaultFetchPageCount)
        if (isNaN(pages))
            return GitHubConstants.defaultFetchPageCount
        return Math.max(GitHubConstants.minFetchPageCount, Math.min(GitHubConstants.maxFetchPageCount, pages))
    }

    function loadFetchPages() {
        fetchPagesValue = clampFetchPages(loadValue("fetchPages", GitHubConstants.defaultFetchPageCount))
    }

    function clampPopupHeight(value) {
        var units = parseInt(value || GitHubConstants.defaultPopupHeightUnits)
        if (isNaN(units))
            return GitHubConstants.defaultPopupHeightUnits
        return Math.max(GitHubConstants.minPopupHeightUnits, Math.min(GitHubConstants.maxPopupHeightUnits, units))
    }

    function loadPopupHeight() {
        popupHeightValue = clampPopupHeight(loadValue("popupHeight", GitHubConstants.defaultPopupHeightUnits))
    }

    function clampCacheTtl(value) {
        var ttl = parseInt(value || GitHubConstants.defaultCacheTtlMinutes)
        if (isNaN(ttl))
            return GitHubConstants.defaultCacheTtlMinutes
        return Math.max(GitHubConstants.minCacheTtlMinutes, Math.min(GitHubConstants.maxCacheTtlMinutes, ttl))
    }

    function loadCacheTtl() {
        cacheTtlValue = clampCacheTtl(loadValue("cacheTtlMinutes", GitHubConstants.defaultCacheTtlMinutes))
    }
    onPluginServiceChanged: {
        if (pluginService) {
            loadToken()
            loadGroupLimit()
            loadFetchPages()
            loadPopupHeight()
            loadCacheTtl()
        }
    }

    Component.onCompleted: {
        loadToken()
        loadGroupLimit()
        loadFetchPages()
        loadPopupHeight()
        loadCacheTtl()
    }

    SecretStore {
        id: secretStore
        pluginService: root.pluginService
        legacyPlainTextToken: root.loadValue("githubToken", "")

        onTokenLoaded: function(token) {
            root.tokenValue = token || ""
            root.tokenSaveFailed = false
            if (!token && statusMessage)
                root.tokenStatusMessage = statusMessage
        }

        onTokenStored: function(success, message) {
            root.tokenSaveFailed = !success
            root.tokenStatusMessage = message
        }

        onTokenCleared: function(success, message) {
            root.tokenSaveFailed = !success
            root.tokenStatusMessage = message
        }
    }

    Timer {
        id: tokenSaveTimer
        interval: 500
        repeat: false
        onTriggered: root.persistToken(tokenInput.text)
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
        text: "Show GitHub inbox messages directly in DankBar and a popup list.\nUse a GitHub classic personal access token with the 'notifications' scope."
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
            onClicked: Qt.openUrlExternally(GitHubConstants.githubTokenSettingsUrl)
        }
    }

    Item {
        width: parent.width
        height: tokenColumn.implicitHeight

        Column {
            id: tokenColumn
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
                height: GitHubConstants.settingsTokenFieldHeightPx
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

                    onTextEdited: tokenSaveTimer.restart()
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
                    anchors.rightMargin: GitHubConstants.settingsVisibilityButtonRightMarginPx
                    anchors.verticalCenter: parent.verticalCenter
                    width: GitHubConstants.settingsVisibilityButtonSizePx
                    height: GitHubConstants.settingsVisibilityButtonSizePx
                    radius: GitHubConstants.settingsVisibilityButtonRadiusPx
                    color: visibilityArea.containsMouse
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.settingsButtonHoverOpacity)
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
                        size: GitHubConstants.settingsVisibilityIconSizePx
                        color: Theme.surfaceVariantText
                    }
                }
            }

            StyledText {
                visible: root.tokenStatusMessage.length > 0
                text: root.tokenStatusMessage
                color: root.tokenSaveFailed ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Refresh Interval"
        description: "How often the widget checks GitHub inbox"
        options: [
            { label: "1 minute", value: "60" },
            { label: "2 minutes", value: "120" },
            { label: "5 minutes", value: "300" },
            { label: "10 minutes", value: "600" },
            { label: "15 minutes", value: "900" }
        ]
        defaultValue: GitHubConstants.defaultPollIntervalSetting
    }

    ToggleSetting {
        settingKey: "loadAuthorInfo"
        label: "Load Author Details"
        description: "Load author avatars and profile names for each message"
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "Note: This will considerably increase message loading time."
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "To enable author details for private repositories, ensure that your token has full 'repo' permissions."
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "enableNotifications"
        label: "Desktop Notifications"
        description: "Show a system notification when new inbox messages arrive"
        defaultValue: GitHubConstants.defaultEnableNotifications
    }

    Item {
        width: parent.width
        height: GitHubConstants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: GitHubConstants.settingsSliderColumnSpacingPx

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
                height: GitHubConstants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: GitHubConstants.settingsSliderTrackHeightPx
                    radius: GitHubConstants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (groupSlider.value - GitHubConstants.minGroupItemLimit) / (GitHubConstants.maxGroupItemLimit - GitHubConstants.minGroupItemLimit) * parent.width
                        height: parent.height
                        radius: GitHubConstants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: groupHandle
                    width: GitHubConstants.settingsSliderHandleSizePx
                    height: GitHubConstants.settingsSliderHandleSizePx
                    radius: GitHubConstants.settingsSliderHandleRadiusPx
                    color: groupMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: GitHubConstants.settingsSliderHandleBorderWidthPx
                    x: (groupSlider.value - GitHubConstants.minGroupItemLimit) / (GitHubConstants.maxGroupItemLimit - GitHubConstants.minGroupItemLimit) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: groupSlider
                    property real value: root.groupLimitValue
                }

                MouseArea {
                    id: groupMouse
                    anchors.fill: parent
                    anchors.topMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        groupSlider.value = Math.round(GitHubConstants.minGroupItemLimit + ratio * (GitHubConstants.maxGroupItemLimit - GitHubConstants.minGroupItemLimit))
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
        height: GitHubConstants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: GitHubConstants.settingsSliderColumnSpacingPx

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
                height: GitHubConstants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: GitHubConstants.settingsSliderTrackHeightPx
                    radius: GitHubConstants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (fetchPagesSlider.value - GitHubConstants.minFetchPageCount) / (GitHubConstants.maxFetchPageCount - GitHubConstants.minFetchPageCount) * parent.width
                        height: parent.height
                        radius: GitHubConstants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: fetchPagesHandle
                    width: GitHubConstants.settingsSliderHandleSizePx
                    height: GitHubConstants.settingsSliderHandleSizePx
                    radius: GitHubConstants.settingsSliderHandleRadiusPx
                    color: fetchPagesMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: GitHubConstants.settingsSliderHandleBorderWidthPx
                    x: (fetchPagesSlider.value - GitHubConstants.minFetchPageCount) / (GitHubConstants.maxFetchPageCount - GitHubConstants.minFetchPageCount) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: fetchPagesSlider
                    property real value: root.fetchPagesValue
                }

                MouseArea {
                    id: fetchPagesMouse
                    anchors.fill: parent
                    anchors.topMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        fetchPagesSlider.value = Math.round(GitHubConstants.minFetchPageCount + ratio * (GitHubConstants.maxFetchPageCount - GitHubConstants.minFetchPageCount))
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
        height: GitHubConstants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: GitHubConstants.settingsSliderColumnSpacingPx

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
                height: GitHubConstants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: GitHubConstants.settingsSliderTrackHeightPx
                    radius: GitHubConstants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (popupHeightSlider.value - GitHubConstants.minPopupHeightUnits) / (GitHubConstants.maxPopupHeightUnits - GitHubConstants.minPopupHeightUnits) * parent.width
                        height: parent.height
                        radius: GitHubConstants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: popupHeightHandle
                    width: GitHubConstants.settingsSliderHandleSizePx
                    height: GitHubConstants.settingsSliderHandleSizePx
                    radius: GitHubConstants.settingsSliderHandleRadiusPx
                    color: popupHeightMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: GitHubConstants.settingsSliderHandleBorderWidthPx
                    x: (popupHeightSlider.value - GitHubConstants.minPopupHeightUnits) / (GitHubConstants.maxPopupHeightUnits - GitHubConstants.minPopupHeightUnits) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: popupHeightSlider
                    property real value: root.popupHeightValue
                }

                MouseArea {
                    id: popupHeightMouse
                    anchors.fill: parent
                    anchors.topMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        popupHeightSlider.value = Math.round(GitHubConstants.minPopupHeightUnits + ratio * (GitHubConstants.maxPopupHeightUnits - GitHubConstants.minPopupHeightUnits))
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
        description: "How many lines each message title can use"
        options: [
            { label: "1 line", value: "1" },
            { label: "2 lines", value: "2" },
            { label: "3 lines", value: "3" },
            { label: "4 lines", value: "4" }
        ]
        defaultValue: GitHubConstants.defaultTitleLines
    }

    // -------------------------------------------------------------------------
    // Cache Settings
    // -------------------------------------------------------------------------

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledText {
        text: "Cache"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Inbox messages, author details, and avatars are cached locally for faster loading.\nAvatars are stored as image files so they load instantly when the popup reopens."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Item {
        width: parent.width
        height: GitHubConstants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: GitHubConstants.settingsSliderColumnSpacingPx

            Row {
                width: parent.width

                StyledText {
                    text: "Cache Freshness (minutes)"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { width: Theme.spacingS; height: 1 }

                StyledText {
                    text: cacheTtlSlider.value.toFixed(0)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Item {
                width: parent.width
                height: GitHubConstants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: GitHubConstants.settingsSliderTrackHeightPx
                    radius: GitHubConstants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (cacheTtlSlider.value - GitHubConstants.minCacheTtlMinutes) / (GitHubConstants.maxCacheTtlMinutes - GitHubConstants.minCacheTtlMinutes) * parent.width
                        height: parent.height
                        radius: GitHubConstants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: cacheTtlHandle
                    width: GitHubConstants.settingsSliderHandleSizePx
                    height: GitHubConstants.settingsSliderHandleSizePx
                    radius: GitHubConstants.settingsSliderHandleRadiusPx
                    color: cacheTtlMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: GitHubConstants.settingsSliderHandleBorderWidthPx
                    x: (cacheTtlSlider.value - GitHubConstants.minCacheTtlMinutes) / (GitHubConstants.maxCacheTtlMinutes - GitHubConstants.minCacheTtlMinutes) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: cacheTtlSlider
                    property real value: root.cacheTtlValue
                }

                MouseArea {
                    id: cacheTtlMouse
                    anchors.fill: parent
                    anchors.topMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -GitHubConstants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        cacheTtlSlider.value = Math.round(GitHubConstants.minCacheTtlMinutes + ratio * (GitHubConstants.maxCacheTtlMinutes - GitHubConstants.minCacheTtlMinutes))
                    }

                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                    onReleased: {
                        var limited = root.clampCacheTtl(cacheTtlSlider.value)
                        cacheTtlSlider.value = limited
                        root.cacheTtlValue = limited
                        root.saveValue("cacheTtlMinutes", String(limited))
                    }
                }
            }
        }
    }

    Rectangle {
        width: clearCacheBtn.width + Theme.spacingM * 2
        height: clearCacheBtn.height + Theme.spacingS
        radius: Theme.cornerRadius
        color: clearCacheArea.containsMouse
               ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
               : Theme.surfaceContainerHigh
        border.width: 1
        border.color: clearCacheArea.containsMouse ? Theme.error : Theme.outlineVariant

        StyledText {
            id: clearCacheBtn
            anchors.centerIn: parent
            text: "Clear Cache"
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: clearCacheArea.containsMouse ? Theme.error : Theme.surfaceText
        }

        MouseArea {
            id: clearCacheArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.saveValue("clearCacheRequested", "true")
        }
    }

    // -------------------------------------------------------------------------
    // API Call Statistics (expandable)
    // -------------------------------------------------------------------------

    Rectangle {
        visible: GitHubConstants.isDevMode
        width: parent.width
        height: visible ? 1 : 0
        color: Theme.outlineVariant
    }

    Item {
        id: statsSection
        property bool statsExpanded: false

        visible: GitHubConstants.isDevMode
        width: parent.width
        height: visible ? Theme.spacingS + statsHeader.height + statsCollapser.height : 0

        MouseArea {
            width: parent.width
            height: statsHeader.height + Theme.spacingS
            anchors.top: parent.top
            cursorShape: Qt.PointingHandCursor
            onClicked: statsSection.statsExpanded = !statsSection.statsExpanded
        }

        Row {
            id: statsHeader
            width: parent.width
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            spacing: Theme.spacingXS

            DankIcon {
                name: statsSection.statsExpanded ? "expand_more" : "chevron_right"
                size: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "API Call Statistics"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            id: statsCollapser
            width: parent.width
            anchors.top: statsHeader.bottom
            height: statsSection.statsExpanded ? statsTable.implicitHeight : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: GitHubConstants.settingsStatsExpandAnimationDurationMs; easing.type: Easing.OutCubic }
            }

            Column {
                id: statsTable
                width: parent.width
                spacing: 2
                topPadding: Theme.spacingXS

                readonly property real c1: width * GitHubConstants.settingsStatsScopeColumnWidthRatio
                readonly property real c2: width * GitHubConstants.settingsStatsCallsColumnWidthRatio
                readonly property real c3: width * GitHubConstants.settingsStatsAvgDurationColumnWidthRatio
                readonly property real c4: width * GitHubConstants.settingsStatsRefreshesColumnWidthRatio

                // ---- Column headers -----------------------------------------
                Row {
                    width: parent.width
                    height: GitHubConstants.settingsStatsHeaderRowHeightPx

                    StyledText {
                        width: statsTable.c1
                        text: "Scope"
                        font.pixelSize: GitHubConstants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                    }
                    StyledText {
                        width: statsTable.c2
                        text: "Calls"
                        font.pixelSize: GitHubConstants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c3
                        text: "Avg sec"
                        font.pixelSize: GitHubConstants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c4
                        text: "Refreshes"
                        font.pixelSize: GitHubConstants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                // ---- Last refresh -------------------------------------------
                Row {
                    width: parent.width
                    height: GitHubConstants.settingsStatsDataRowHeightPx

                    StyledText {
                        width: statsTable.c1
                        text: "Last refresh"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: statsTable.c2
                        text: ApiCallStats.lastSessionCalls > 0 ? ApiCallStats.lastSessionCalls.toString() : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c3
                        text: ApiCallStats.lastSessionCalls > 0
                              ? (ApiCallStats.lastSessionSleepDetected ? "\u2014" : ApiCallStats.lastSessionDurationSecs.toFixed(1) + "s")
                              : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c4
                        text: ApiCallStats.lastSessionCalls > 0 ? "1" : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // ---- Last hour ----------------------------------------------
                Row {
                    width: parent.width
                    height: GitHubConstants.settingsStatsDataRowHeightPx

                    StyledText {
                        width: statsTable.c1
                        text: "Last hour"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: statsTable.c2
                        text: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourCalls.toString() : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c3
                        text: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourAvgDurationSecs.toFixed(1) + "s" : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c4
                        text: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourRefreshCount.toString() : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // ---- All time -----------------------------------------------
                Row {
                    width: parent.width
                    height: GitHubConstants.settingsStatsDataRowHeightPx

                    StyledText {
                        width: statsTable.c1
                        text: "All time"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: statsTable.c2
                        text: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalCalls.toString() : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c3
                        text: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalAvgDurationSecs.toFixed(1) + "s" : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c4
                        text: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalRefreshCount.toString() : "\u2014"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item { width: 1; height: Theme.spacingXS }
            }
        }
    }
}
