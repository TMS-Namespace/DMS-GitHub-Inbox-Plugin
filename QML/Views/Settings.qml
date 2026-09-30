// Settings.qml - Settings page for GitHub Inbox plugin

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import ".."

PluginSettings {
    id: root
    pluginId: GitHubConstants.pluginNamespaceId

    property string tokenValue: ""
    property var missingDependencies: []
    property bool dependenciesChecked: false
    readonly property bool dependenciesReady: dependenciesChecked && missingDependencies.length === 0
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
            secretStore.storeToken(trimmed)
        else
            secretStore.clearToken()
    }


    onPluginServiceChanged: {
        if (pluginService) {
            loadToken()
            settingsContent.loadValue()
        }
    }

    Component.onCompleted: {
        loadToken()
        if (pluginService)
            settingsContent.loadValue()
        checkDependencies()
    }

    function checkDependencies() {
        if (dependencyCheck.running)
            return
        dependencyCheck.command = ["bash", "-c",
            "for dep in \"$@\"; do command -v \"$dep\" >/dev/null 2>&1 || printf '%s\\n' \"$dep\"; done",
            "github-inbox-dependencies"].concat(GitHubConstants.requiredCommands)
        dependencyCheck.running = true
    }

    Process {
        id: dependencyCheck
        property string output: ""
        stdout: SplitParser { onRead: line => dependencyCheck.output += line + "\n" }
        onExited: exitCode => {
            root.missingDependencies = exitCode === 0
                ? dependencyCheck.output.split("\n").filter(name => name.length > 0)
                : GitHubConstants.requiredCommands
            root.dependenciesChecked = true
            dependencyCheck.output = ""
        }
    }

    SecretStore {
        id: secretStore
        pluginService: root.pluginService

        onTokenLoaded: function(token) {
            root.tokenValue = token || ""
            tokenInput.text = root.tokenValue
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

    StyledText {
        visible: !root.dependenciesReady
        width: parent.width
        text: root.dependenciesChecked
            ? "Missing required commands: " + root.missingDependencies.join(", ")
              + ". GitHub Inbox cannot work until they are installed."
            : "Checking required commands..."
        color: Theme.error
        font.pixelSize: Theme.fontSizeMedium
        wrapMode: Text.WordWrap
    }

    Column {
        id: settingsContent
        width: parent.width
        spacing: Theme.spacingM
        visible: root.dependenciesReady
        height: visible ? implicitHeight : 0

        function loadValue() {
            for (var child of children)
                if (child.loadValue)
                    child.loadValue()
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
            text: "Use a GitHub classic personal access token with at least the 'notifications' scope."
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

                DankTextField {
                    id: tokenInput
                    width: parent.width
                    height: Math.round(Theme.fontSizeMedium * 3)
                    placeholderText: "ghp_..."
                    showPasswordToggle: true
                    echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
                    text: root.tokenValue
                    onTextEdited: {
                        if (text !== root.tokenValue) {
                            root.tokenValue = text
                            tokenSaveTimer.restart()
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

        SliderSetting {
            id: groupSliderSetting
            settingKey: "groupItemLimit"
            label: "Max Items Per Group"
            minimum: GitHubConstants.minGroupItemLimit
            maximum: GitHubConstants.maxGroupItemLimit
            defaultValue: GitHubConstants.defaultGroupItemLimit
        }

        SliderSetting {
            id: popupHeightSliderSetting
            settingKey: "popupHeight"
            label: "Popup Height"
            minimum: GitHubConstants.minPopupHeightUnits
            maximum: GitHubConstants.maxPopupHeightUnits
            defaultValue: GitHubConstants.defaultPopupHeightUnits
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
            text: "Inbox messages, author details, and avatars are cached locally for faster loading."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
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
            visible: GitHubConstants.apiCallStatsEnabled
            width: parent.width
            height: visible ? 1 : 0
            color: Theme.outlineVariant
        }

        Item {
            id: statsSection
            property bool statsExpanded: false

            visible: GitHubConstants.apiCallStatsEnabled
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
                    spacing: Math.max(0, (Theme.spacingXXS || 0) + GitHubConstants.settingsStatsRowSpacingDelta)
                    topPadding: Theme.spacingXS

                    readonly property real c1: width * GitHubConstants.settingsStatsScopeColumnWidthRatio
                    readonly property real c2: width * GitHubConstants.settingsStatsCallsColumnWidthRatio
                    readonly property real c3: width * GitHubConstants.settingsStatsAvgDurationColumnWidthRatio
                    readonly property real c4: width * GitHubConstants.settingsStatsRefreshesColumnWidthRatio

                    // ---- Column headers -----------------------------------------
                    Row {
                        width: parent.width
                        height: Theme.fontSizeSmall + GitHubConstants.settingsStatsHeaderRowHeightDelta

                        StyledText {
                            width: statsTable.c1
                            text: "Scope"
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.settingsStatsFontSizeDelta
                            color: Theme.surfaceVariantText
                            font.weight: Font.Medium
                        }
                        StyledText {
                            width: statsTable.c2
                            text: "Calls"
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.settingsStatsFontSizeDelta
                            color: Theme.surfaceVariantText
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                        }
                        StyledText {
                            width: statsTable.c3
                            text: "Avg sec"
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.settingsStatsFontSizeDelta
                            color: Theme.surfaceVariantText
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                        }
                        StyledText {
                            width: statsTable.c4
                            text: "Refreshes"
                            font.pixelSize: Theme.fontSizeSmall + GitHubConstants.settingsStatsFontSizeDelta
                            color: Theme.surfaceVariantText
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                    // ---- Last refresh -------------------------------------------
                    Row {
                        width: parent.width
                        height: Theme.fontSizeSmall + GitHubConstants.settingsStatsDataRowHeightDelta

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
                        height: Theme.fontSizeSmall + GitHubConstants.settingsStatsDataRowHeightDelta

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
                        height: Theme.fontSizeSmall + GitHubConstants.settingsStatsDataRowHeightDelta

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
}
