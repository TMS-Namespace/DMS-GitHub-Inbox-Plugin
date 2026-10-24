// SettingsApiStatsView.qml - expandable API request statistics table.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets

Item {
    id: statsView

    property bool expanded: false
    readonly property var rows: [
        {
            scope: "Last refresh",
            calls: ApiCallStats.lastSessionCalls > 0 ? ApiCallStats.lastSessionCalls.toString() : "-",
            average: ApiCallStats.lastSessionCalls > 0 ? (ApiCallStats.lastSessionSleepDetected ? "-" : ApiCallStats.lastSessionDurationSecs.toFixed(1) + "s") : "-",
            refreshes: ApiCallStats.lastSessionCalls > 0 ? "1" : "-"
        },
        {
            scope: "Last hour",
            calls: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourCalls.toString() : "-",
            average: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourAvgDurationSecs.toFixed(1) + "s" : "-",
            refreshes: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourRefreshCount.toString() : "-"
        },
        {
            scope: "All time",
            calls: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalCalls.toString() : "-",
            average: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalAvgDurationSecs.toFixed(1) + "s" : "-",
            refreshes: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalRefreshCount.toString() : "-"
        }
    ]

    height: visible ? Theme.spacingS + header.height + statsClip.height : 0
    objectName: "apiCallStatsView"
    visible: GitHubConstants.apiCallStatsEnabled
    width: parent.width

    Rectangle {
        anchors.top: parent.top
        color: Theme.outlineVariant
        height: 1
        visible: statsView.visible
        width: parent.width
    }
    MouseArea {
        anchors.fill: header
        cursorShape: Qt.PointingHandCursor

        onClicked: statsView.expanded = !statsView.expanded
    }
    Row {
        id: header

        anchors.top: parent.top
        anchors.topMargin: Theme.spacingS
        spacing: Theme.spacingXS
        width: parent.width

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceVariantText
            name: statsView.expanded ? "expand_more" : "chevron_right"
            size: Theme.fontSizeMedium
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            text: "API Call Statistics"
        }
    }
    Item {
        id: statsClip

        anchors.top: header.bottom
        clip: true
        height: statsView.expanded ? statsTable.implicitHeight + Theme.spacingXS : 0
        width: parent.width

        Behavior on height {
            NumberAnimation {
                duration: GitHubConstants.settingsStatsExpandAnimationDurationMs
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: statsTable

            readonly property real averageColumnWidth: width * GitHubConstants.settingsStatsAvgDurationColumnWidthRatio
            readonly property real callsColumnWidth: width * GitHubConstants.settingsStatsCallsColumnWidthRatio
            readonly property real refreshesColumnWidth: width * GitHubConstants.settingsStatsRefreshesColumnWidthRatio
            readonly property real scopeColumnWidth: width * GitHubConstants.settingsStatsScopeColumnWidthRatio

            spacing: Math.max(0, (Theme.spacingXXS || 0) + GitHubConstants.settingsStatsRowSpacingDelta)
            topPadding: Theme.spacingXS
            width: parent.width

            Row {
                height: Theme.fontSizeSmall + GitHubConstants.settingsStatsHeaderRowHeightDelta
                width: parent.width

                Repeater {
                    model: [
                        {
                            text: "Scope",
                            width: statsTable.scopeColumnWidth,
                            alignment: Text.AlignLeft
                        },
                        {
                            text: "Calls",
                            width: statsTable.callsColumnWidth,
                            alignment: Text.AlignHCenter
                        },
                        {
                            text: "Avg sec",
                            width: statsTable.averageColumnWidth,
                            alignment: Text.AlignHCenter
                        },
                        {
                            text: "Refreshes",
                            width: statsTable.refreshesColumnWidth,
                            alignment: Text.AlignHCenter
                        }
                    ]

                    delegate: StyledText {
                        required property var modelData

                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall + GitHubConstants.settingsStatsFontSizeDelta
                        font.weight: Font.Medium
                        horizontalAlignment: modelData.alignment
                        text: modelData.text
                        width: modelData.width
                    }
                }
            }
            Rectangle {
                color: Theme.outlineVariant
                height: 1
                opacity: 0.5
                width: parent.width
            }
            Repeater {
                model: statsView.rows

                delegate: Row {
                    id: statsRow

                    required property var modelData

                    height: Theme.fontSizeSmall + GitHubConstants.settingsStatsDataRowHeightDelta
                    width: statsTable.width

                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        text: statsRow.modelData.scope
                        width: statsTable.scopeColumnWidth
                    }
                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        text: statsRow.modelData.calls
                        width: statsTable.callsColumnWidth
                    }
                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        text: statsRow.modelData.average
                        width: statsTable.averageColumnWidth
                    }
                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        text: statsRow.modelData.refreshes
                        width: statsTable.refreshesColumnWidth
                    }
                }
            }
        }
    }
}
