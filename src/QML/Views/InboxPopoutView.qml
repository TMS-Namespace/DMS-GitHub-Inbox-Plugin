// InboxPopoutView.qml - popup presentation and UI events for the inbox.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PopoutComponent {
    id: view

    property var authorsByThread: ({})
    property string details: ""
    property string errorMessage: ""
    property var expandedDateGroupsState: ({})
    property var expandedReposState: ({})
    property int groupItemLimit: GitHubConstants.defaultGroupItemLimit
    property string groupingMode: "repo"
    property real inboxHeight: 600
    property bool isAuthorFetching: false
    property bool isDownloadingAvatars: false
    property bool isLoading: false
    property bool isOperating: false
    property real lastUpdated: 0
    property var messages: []
    property string participationFilter: "both"
    property bool popupOpen: false
    property string readFilter: "both"
    property bool showAuthorInfo: true
    property int titleLines: GitHubConstants.defaultTitleLines
    property bool tokenConfigured: false
    property int unreadCount: 0

    signal closeRequested
    signal groupingModeChangedByUser(string value)
    signal markAllRead
    signal markDateGroupDone(var items)
    signal markDateGroupRead(var items)
    signal markRepoDone(var items)
    signal markRepoRead(var items)
    signal markThreadDone(string threadId)
    signal markThreadRead(string threadId)
    signal markThreadReadAfterOpen(string threadId)
    signal markThreadUnread(string threadId)
    signal participationFilterChangedByUser(string value)
    signal persistExpandedDateGroups(var state)
    signal persistExpandedRepos(var state)
    signal popoutVisibilityChanged(bool visible)
    signal readFilterChangedByUser(string value)
    signal refreshNow
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)

    // Publish the host popup visibility after late parent attachment and subsequent changes.
    function syncPopoutVisibility() {
        popoutVisibilityChanged(!!(parentPopout && parentPopout.shouldBeVisible));
    }

    detailsText: ""
    headerText: "GitHub Inbox"
    showCloseButton: false

    Component.onCompleted: Qt.callLater(syncPopoutVisibility)
    Component.onDestruction: popoutVisibilityChanged(false)
    onParentPopoutChanged: syncPopoutVisibility()

    Connections {
        // Handle this workflow result at the ownership boundary and preserve failure visibility.
        function onShouldBeVisibleChanged() {
            view.syncPopoutVisibility();
        }

        target: view.parentPopout
    }
    Item {
        id: detailsRow

        height: GitHubConstants.popoutFilterSegmentHeightPx + Theme.spacingS
        width: parent.width

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.right: groupingControl.visible ? groupingControl.left : parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: groupingControl.visible ? groupingControl.verticalCenter : parent.verticalCenter
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            maximumLineCount: 1
            text: view.details
            wrapMode: Text.NoWrap
        }
        Row {
            id: groupingControl

            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.top: parent.top
            height: GitHubConstants.popoutFilterSegmentHeightPx
            spacing: Theme.spacingXS
            visible: view.tokenConfigured

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                text: "Group By"
            }
            Rectangle {
                border.color: Theme.outlineMedium
                border.width: 1
                color: Theme.nestedSurface
                height: GitHubConstants.popoutFilterSegmentHeightPx
                radius: Theme.cornerRadius
                width: GitHubConstants.popoutFilterSegmentMinWidthPx

                Row {
                    id: groupingModeSegments

                    anchors.fill: parent
                    spacing: Math.max(1, (Theme.spacingXXS || 0) + GitHubConstants.popoutFilterSegmentSpacingDelta)

                    Repeater {
                        model: [
                            {
                                label: "Repo",
                                value: "repo"
                            },
                            {
                                label: "Date",
                                value: "date"
                            }
                        ]

                        delegate: Rectangle {
                            id: groupingModeOption

                            required property var modelData

                            color: view.groupingMode === modelData.value ? Theme.withAlpha(Theme.primary, GitHubConstants.popoutFilterActiveTintOpacity) : "transparent"
                            height: parent.height
                            radius: Theme.cornerRadius
                            width: (groupingModeSegments.width - groupingModeSegments.spacing) / 2

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor

                                onClicked: view.groupingModeChangedByUser(groupingModeOption.modelData.value)
                            }
                            StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                color: view.groupingMode === groupingModeOption.modelData.value ? Theme.primary : Theme.surfaceVariantText
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: view.groupingMode === groupingModeOption.modelData.value ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                text: groupingModeOption.modelData.label
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }
    PopoutPanel {
        authorsByThread: view.authorsByThread
        errorMessage: view.errorMessage
        expandedDateGroupsState: view.expandedDateGroupsState
        expandedReposState: view.expandedReposState
        groupItemLimit: view.groupItemLimit
        groupingMode: view.groupingMode
        headerHoverBottomInset: detailsRow.height
        headerHoverHeight: view.headerHeight
        headerOffset: view.headerHeight + detailsRow.height
        implicitHeight: view.inboxHeight - view.headerHeight - detailsRow.height - Theme.spacingXL
        isAuthorFetching: view.isAuthorFetching
        isDownloadingAvatars: view.isDownloadingAvatars
        isLoading: view.isLoading
        isOperating: view.isOperating
        lastUpdated: view.lastUpdated
        messages: view.messages
        participationFilter: view.participationFilter
        popupOpen: view.popupOpen
        readFilter: view.readFilter
        showAuthorInfo: view.showAuthorInfo
        titleLines: view.titleLines
        tokenConfigured: view.tokenConfigured
        unreadCount: view.unreadCount
        width: parent.width

        onClosePopout: view.closeRequested()
        onMarkAllRead: view.markAllRead()
        onMarkDateGroupDone: function (items) {
            view.markDateGroupDone(items);
        }
        onMarkDateGroupRead: function (items) {
            view.markDateGroupRead(items);
        }
        onMarkRepoDone: function (items) {
            view.markRepoDone(items);
        }
        onMarkRepoRead: function (items) {
            view.markRepoRead(items);
        }
        onMarkThreadDone: function (threadId) {
            view.markThreadDone(threadId);
        }
        onMarkThreadRead: function (threadId) {
            view.markThreadRead(threadId);
        }
        onMarkThreadReadAfterOpen: function (threadId) {
            view.markThreadReadAfterOpen(threadId);
        }
        onMarkThreadUnread: function (threadId) {
            view.markThreadUnread(threadId);
        }
        onParticipationFilterChangedByUser: function (value) {
            view.participationFilterChangedByUser(value);
        }
        onPersistExpandedDateGroups: function (state) {
            view.persistExpandedDateGroups(state);
        }
        onPersistExpandedRepos: function (state) {
            view.persistExpandedRepos(state);
        }
        onReadFilterChangedByUser: function (value) {
            view.readFilterChangedByUser(value);
        }
        onRefreshNow: view.refreshNow()
        onRequestThreadAuthors: function (threadId, subjectApiUrl, subjectType) {
            view.requestThreadAuthors(threadId, subjectApiUrl, subjectType);
        }
    }
}
