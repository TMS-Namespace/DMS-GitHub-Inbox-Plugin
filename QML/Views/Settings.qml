// Settings.qml - Settings page for GitHub Inbox plugin

import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import ".."

PluginSettings {
    id: root
    pluginId: Constants.pluginNamespaceId

    property string tokenValue: ""
    property bool showToken: false
    property int groupLimitValue: Constants.defaultGroupItemLimit
    property int fetchPagesValue: Constants.defaultFetchPageCount
    property int popupHeightValue: Constants.defaultPopupHeightUnits
    property int cacheTtlValue: Constants.defaultCacheTtlMinutes

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
        var limit = parseInt(value || Constants.defaultGroupItemLimit)
        if (isNaN(limit))
            return Constants.defaultGroupItemLimit
        return Math.max(Constants.minGroupItemLimit, Math.min(Constants.maxGroupItemLimit, limit))
    }

    function loadGroupLimit() {
        groupLimitValue = clampGroupLimit(loadValue("groupItemLimit", Constants.defaultGroupItemLimit))
    }

    function clampFetchPages(value) {
        var pages = parseInt(value || Constants.defaultFetchPageCount)
        if (isNaN(pages))
            return Constants.defaultFetchPageCount
        return Math.max(Constants.minFetchPageCount, Math.min(Constants.maxFetchPageCount, pages))
    }

    function loadFetchPages() {
        fetchPagesValue = clampFetchPages(loadValue("fetchPages", Constants.defaultFetchPageCount))
    }

    function clampPopupHeight(value) {
        var units = parseInt(value || Constants.defaultPopupHeightUnits)
        if (isNaN(units))
            return Constants.defaultPopupHeightUnits
        return Math.max(Constants.minPopupHeightUnits, Math.min(Constants.maxPopupHeightUnits, units))
    }

    function loadPopupHeight() {
        popupHeightValue = clampPopupHeight(loadValue("popupHeight", Constants.defaultPopupHeightUnits))
    }

    function clampCacheTtl(value) {
        var ttl = parseInt(value || Constants.defaultCacheTtlMinutes)
        if (isNaN(ttl))
            return Constants.defaultCacheTtlMinutes
        return Math.max(Constants.minCacheTtlMinutes, Math.min(Constants.maxCacheTtlMinutes, ttl))
    }

    function loadCacheTtl() {
        cacheTtlValue = clampCacheTtl(loadValue("cacheTtlMinutes", Constants.defaultCacheTtlMinutes))
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
            onClicked: Qt.openUrlExternally(Constants.githubTokenSettingsUrl)
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
                    anchors.rightMargin: Constants.settingsVisibilityButtonRightMarginPx
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.settingsVisibilityButtonSizePx
                    height: Constants.settingsVisibilityButtonSizePx
                    radius: Constants.settingsVisibilityButtonRadiusPx
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
                        size: Constants.settingsVisibilityIconSizePx
                        color: Theme.surfaceVariantText
                    }
                }
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
        defaultValue: Constants.defaultPollIntervalSetting
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

    Item {
        width: parent.width
        height: Constants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: Constants.settingsSliderColumnSpacingPx

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
                height: Constants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Constants.settingsSliderTrackHeightPx
                    radius: Constants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (groupSlider.value - Constants.minGroupItemLimit) / (Constants.maxGroupItemLimit - Constants.minGroupItemLimit) * parent.width
                        height: parent.height
                        radius: Constants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: groupHandle
                    width: Constants.settingsSliderHandleSizePx
                    height: Constants.settingsSliderHandleSizePx
                    radius: Constants.settingsSliderHandleRadiusPx
                    color: groupMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: Constants.settingsSliderHandleBorderWidthPx
                    x: (groupSlider.value - Constants.minGroupItemLimit) / (Constants.maxGroupItemLimit - Constants.minGroupItemLimit) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: groupSlider
                    property real value: root.groupLimitValue
                }

                MouseArea {
                    id: groupMouse
                    anchors.fill: parent
                    anchors.topMargin: -Constants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -Constants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        groupSlider.value = Math.round(Constants.minGroupItemLimit + ratio * (Constants.maxGroupItemLimit - Constants.minGroupItemLimit))
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
        height: Constants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: Constants.settingsSliderColumnSpacingPx

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
                height: Constants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Constants.settingsSliderTrackHeightPx
                    radius: Constants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (fetchPagesSlider.value - Constants.minFetchPageCount) / (Constants.maxFetchPageCount - Constants.minFetchPageCount) * parent.width
                        height: parent.height
                        radius: Constants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: fetchPagesHandle
                    width: Constants.settingsSliderHandleSizePx
                    height: Constants.settingsSliderHandleSizePx
                    radius: Constants.settingsSliderHandleRadiusPx
                    color: fetchPagesMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: Constants.settingsSliderHandleBorderWidthPx
                    x: (fetchPagesSlider.value - Constants.minFetchPageCount) / (Constants.maxFetchPageCount - Constants.minFetchPageCount) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: fetchPagesSlider
                    property real value: root.fetchPagesValue
                }

                MouseArea {
                    id: fetchPagesMouse
                    anchors.fill: parent
                    anchors.topMargin: -Constants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -Constants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        fetchPagesSlider.value = Math.round(Constants.minFetchPageCount + ratio * (Constants.maxFetchPageCount - Constants.minFetchPageCount))
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
        height: Constants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: Constants.settingsSliderColumnSpacingPx

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
                height: Constants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Constants.settingsSliderTrackHeightPx
                    radius: Constants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (popupHeightSlider.value - Constants.minPopupHeightUnits) / (Constants.maxPopupHeightUnits - Constants.minPopupHeightUnits) * parent.width
                        height: parent.height
                        radius: Constants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: popupHeightHandle
                    width: Constants.settingsSliderHandleSizePx
                    height: Constants.settingsSliderHandleSizePx
                    radius: Constants.settingsSliderHandleRadiusPx
                    color: popupHeightMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: Constants.settingsSliderHandleBorderWidthPx
                    x: (popupHeightSlider.value - Constants.minPopupHeightUnits) / (Constants.maxPopupHeightUnits - Constants.minPopupHeightUnits) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: popupHeightSlider
                    property real value: root.popupHeightValue
                }

                MouseArea {
                    id: popupHeightMouse
                    anchors.fill: parent
                    anchors.topMargin: -Constants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -Constants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        popupHeightSlider.value = Math.round(Constants.minPopupHeightUnits + ratio * (Constants.maxPopupHeightUnits - Constants.minPopupHeightUnits))
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
        defaultValue: Constants.defaultTitleLines
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
        height: Constants.settingsSliderItemHeightPx

        Column {
            anchors.fill: parent
            spacing: Constants.settingsSliderColumnSpacingPx

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
                height: Constants.settingsSliderKnobAreaHeightPx

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Constants.settingsSliderTrackHeightPx
                    radius: Constants.settingsSliderTrackRadiusPx
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: (cacheTtlSlider.value - Constants.minCacheTtlMinutes) / (Constants.maxCacheTtlMinutes - Constants.minCacheTtlMinutes) * parent.width
                        height: parent.height
                        radius: Constants.settingsSliderTrackRadiusPx
                        color: Theme.primary
                    }
                }

                Rectangle {
                    id: cacheTtlHandle
                    width: Constants.settingsSliderHandleSizePx
                    height: Constants.settingsSliderHandleSizePx
                    radius: Constants.settingsSliderHandleRadiusPx
                    color: cacheTtlMouse.pressed ? Theme.primary : Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: Constants.settingsSliderHandleBorderWidthPx
                    x: (cacheTtlSlider.value - Constants.minCacheTtlMinutes) / (Constants.maxCacheTtlMinutes - Constants.minCacheTtlMinutes) * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                }

                QtObject {
                    id: cacheTtlSlider
                    property real value: root.cacheTtlValue
                }

                MouseArea {
                    id: cacheTtlMouse
                    anchors.fill: parent
                    anchors.topMargin: -Constants.settingsSliderTouchExpansionPx
                    anchors.bottomMargin: -Constants.settingsSliderTouchExpansionPx
                    cursorShape: Qt.PointingHandCursor

                    function updateValue(mouseX) {
                        var ratio = Math.max(0, Math.min(1, mouseX / width))
                        cacheTtlSlider.value = Math.round(Constants.minCacheTtlMinutes + ratio * (Constants.maxCacheTtlMinutes - Constants.minCacheTtlMinutes))
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
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    Item {
        id: statsSection
        property bool statsExpanded: false

        width: parent.width
        height: Theme.spacingS + statsHeader.height + statsCollapser.height

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
                NumberAnimation { duration: Constants.settingsStatsExpandAnimationDurationMs; easing.type: Easing.OutCubic }
            }

            Column {
                id: statsTable
                width: parent.width
                spacing: 2
                topPadding: Theme.spacingXS

                readonly property real c1: width * Constants.settingsStatsScopeColumnWidthRatio
                readonly property real c2: width * Constants.settingsStatsCallsColumnWidthRatio
                readonly property real c3: width * Constants.settingsStatsAvgDurationColumnWidthRatio
                readonly property real c4: width * Constants.settingsStatsRefreshesColumnWidthRatio

                // ---- Column headers -----------------------------------------
                Row {
                    width: parent.width
                    height: Constants.settingsStatsHeaderRowHeightPx

                    StyledText {
                        width: statsTable.c1
                        text: "Scope"
                        font.pixelSize: Constants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                    }
                    StyledText {
                        width: statsTable.c2
                        text: "Calls"
                        font.pixelSize: Constants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c3
                        text: "Avg sec"
                        font.pixelSize: Constants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: statsTable.c4
                        text: "Refreshes"
                        font.pixelSize: Constants.settingsStatsFontSizePx
                        color: Theme.surfaceVariantText
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                // ---- Last refresh -------------------------------------------
                Row {
                    width: parent.width
                    height: Constants.settingsStatsDataRowHeightPx

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
                    height: Constants.settingsStatsDataRowHeightPx

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
                    height: Constants.settingsStatsDataRowHeightPx

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
