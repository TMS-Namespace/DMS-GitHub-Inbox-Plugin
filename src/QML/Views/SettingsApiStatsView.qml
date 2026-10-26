// SettingsApiStatsView.qml - expandable API request statistics table.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import qs.Common
import qs.DCommon.Widgets

DCollapsibleSection {
    id: statsView

    readonly property var rows: [
        {
            scope: "Last refresh",
            calls: ApiCallStats.lastSessionCalls > 0 ? ApiCallStats.lastSessionCalls.toString() : "-",
            average: ApiCallStats.lastSessionCalls > 0 ? (ApiCallStats.lastSessionSleepDetected ? "-" : ApiCallStats.lastSessionDurationSecs.toFixed(1) + "s") : "-",
            refreshes: ApiCallStats.lastSessionCalls > 0 ? "1" : "-"
        },
        {
            scope: "Last hour",
            calls: ApiCallStats.lastHourCalls > 0 ? ApiCallStats.lastHourCalls.toString() : "-",
            average: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourAvgDurationSecs.toFixed(1) + "s" : "-",
            refreshes: ApiCallStats.lastHourRefreshCount > 0 ? ApiCallStats.lastHourRefreshCount.toString() : "-"
        },
        {
            scope: "All time",
            calls: ApiCallStats.totalCalls > 0 ? ApiCallStats.totalCalls.toString() : "-",
            average: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalAvgDurationSecs.toFixed(1) + "s" : "-",
            refreshes: ApiCallStats.totalRefreshCount > 0 ? ApiCallStats.totalRefreshCount.toString() : "-"
        }
    ]

    objectName: "apiCallStatsView"
    title: "API Statistics"
    visible: GitHubConstants.apiCallStatsEnabled
    width: parent.width

    Column {
        id: statsTable

        readonly property real averageColumnWidth: width * GitHubConstants.settingsStatsAvgDurationColumnWidthRatio
        readonly property real callsColumnWidth: width * GitHubConstants.settingsStatsCallsColumnWidthRatio
        readonly property real refreshesColumnWidth: width * GitHubConstants.settingsStatsRefreshesColumnWidthRatio
        readonly property real scopeColumnWidth: width * GitHubConstants.settingsStatsScopeColumnWidthRatio

        Layout.fillWidth: true
        spacing: Math.max(0, (Theme.spacingXXS || 0) + GitHubConstants.settingsStatsRowSpacingDelta)
        topPadding: Theme.spacingXS

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
                    objectName: "apiStatsCalls-" + statsRow.modelData.scope
                    text: statsRow.modelData.calls
                    width: statsTable.callsColumnWidth
                }
                StyledText {
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    objectName: "apiStatsDuration-" + statsRow.modelData.scope
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
