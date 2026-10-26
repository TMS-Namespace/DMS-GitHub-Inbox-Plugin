// RepoGroupingGroupView.qml - expandable message group for one repository.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: groupCard

    property var authorsByThread: ({})
    property bool expanded: false
    property var groupData: ({})
    readonly property bool hasActionItems: actionItems().length > 0
    readonly property bool hasUnreadActionItems: visibleUnreadCount() > 0
    property bool headerActionsHovered: repoHeaderArea.containsMouse || repoReadArea.hovered || repoDoneArea.hovered
    property bool isBusy: false
    property bool showAuthorInfo: true
    property int titleLines: GitHubConstants.defaultTitleLines

    signal closePopout
    signal markRepoDone(var items)
    signal markRepoRead(var items)
    signal markThreadDone(string threadId)
    signal markThreadRead(string threadId)
    signal markThreadReadAfterOpen(string threadId)
    signal markThreadUnread(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal toggleExpanded

    // Use the full group membership for bulk actions rather than only its visible rows.
    function actionItems() {
        return groupData.items || [];
    }
    // Keep counts consistent with complete group membership.
    function countItems() {
        return groupData.allItems || groupData.items || [];
    }
    // Count actionable unread items for the group's read control.
    function visibleUnreadCount() {
        let unread = 0;
        let items = actionItems();
        for (let index = 0; index < items.length; index++) {
            if (items[index] && items[index].unread)
                unread++;
        }
        return unread;
    }

    border.color: Theme.outlineMedium
    border.width: 1
    color: Theme.nestedSurface
    implicitHeight: groupColumn.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadius

    Column {
        id: groupColumn

        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS + GitHubConstants.popoutGroupContentHorizontalInsetDelta
        anchors.margins: Theme.spacingS
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS + GitHubConstants.popoutGroupContentHorizontalInsetDelta
        anchors.top: parent.top
        spacing: Theme.spacingS

        Item {
            id: repoHeader

            height: Theme.fontSizeMedium + GitHubConstants.popoutRepoHeaderHeightDelta
            width: parent.width

            MouseArea {
                id: repoHeaderArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: groupCard.toggleExpanded()
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS + GitHubConstants.popoutGroupHeaderLeadingInsetDelta
                anchors.right: repoMeta.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    height: GitHubConstants.popoutRepoAvatarSizePx
                    width: GitHubConstants.popoutRepoAvatarSizePx

                    RoundedAvatar {
                        anchors.fill: parent
                        fallbackIcon: "folder"
                        fallbackIconSize: GitHubConstants.popoutRepoAvatarFallbackIconSizePx
                        source: groupCard.groupData.repoAvatarUrl || ""
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    text: groupCard.groupData.repository || ""
                    width: parent.width - 30
                }
            }
            Row {
                id: repoMeta

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DActionButton {
                    id: repoReadArea

                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
                    buttonSize: GitHubConstants.popoutRepoDoneButtonSizePx
                    enabled: !groupCard.isBusy && groupCard.hasUnreadActionItems
                    iconColor: repoReadArea.hovered ? Theme.primary : Theme.surfaceText
                    iconName: "mark_email_read"
                    iconSize: GitHubConstants.popoutRepoDoneIconSizePx
                    objectName: "groupReadButton"
                    opacity: groupCard.hasUnreadActionItems && groupCard.headerActionsHovered ? 1 : 0
                    radius: width / 2
                    tooltipText: groupCard.isBusy ? "Not available during refresh" : "Mark group as read"
                    visible: groupCard.expanded && groupCard.hasActionItems

                    onClicked: groupCard.markRepoRead(groupCard.actionItems())
                }
                DActionButton {
                    id: repoDoneArea

                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, GitHubConstants.actionButtonBackgroundOpacity)
                    buttonSize: GitHubConstants.popoutRepoDoneButtonSizePx
                    enabled: !groupCard.isBusy
                    iconColor: repoDoneArea.hovered ? Theme.primary : Theme.surfaceText
                    iconName: "done"
                    iconSize: GitHubConstants.popoutRepoDoneIconSizePx
                    objectName: "groupDoneButton"
                    opacity: groupCard.headerActionsHovered ? 1 : 0
                    radius: width / 2
                    tooltipText: groupCard.isBusy ? "Not available during refresh" : "Mark group as done"
                    visible: groupCard.expanded && groupCard.hasActionItems

                    onClicked: groupCard.markRepoDone(groupCard.actionItems())
                }
                Rectangle {
                    color: (groupCard.groupData.unreadCount || 0) > 0 ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutRepoCountBadgeUnreadOpacity) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, GitHubConstants.popoutRepoCountBadgeReadOpacity)
                    height: Theme.fontSizeSmall + GitHubConstants.popoutRepoCountBadgeHeightDelta
                    radius: Math.max(0, Math.min(height / 2, Theme.cornerRadius + GitHubConstants.popoutRepoCountBadgeRadiusDelta))
                    visible: groupCard.hasActionItems
                    width: groupCountText.implicitWidth + Theme.spacingS

                    StyledText {
                        id: groupCountText

                        anchors.centerIn: parent
                        color: (groupCard.groupData.unreadCount || 0) > 0 ? Theme.primary : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall + GitHubConstants.popoutRepoCountFontSizeDelta
                        font.weight: Font.Medium
                        text: {
                            let items = groupCard.countItems();
                            let unread = groupCard.groupData.unreadCount || 0;
                            return unread < items.length ? (unread + "/" + items.length) : String(items.length);
                        }
                    }
                }
                DIcon {
                    color: Theme.surfaceVariantText
                    name: "expand_more"
                    rotation: groupCard.expanded ? 0 : -90
                    size: GitHubConstants.popoutRepoExpandIconSizePx

                    Behavior on rotation {
                        NumberAnimation {
                            duration: GitHubConstants.popoutRepoExpandRotationDurationMs
                        }
                    }
                }
            }
        }
        Column {
            id: repoItems

            clip: true
            height: visible ? implicitHeight : 0
            spacing: Theme.spacingXS
            visible: groupCard.expanded
            width: parent.width

            Repeater {
                model: groupCard.groupData.items || []

                delegate: InboxMessageRow {
                    id: messageDelegate

                    required property var modelData

                    allowAuthorRequests: false
                    authors: groupCard.showAuthorInfo ? (groupCard.authorsByThread[messageDelegate.modelData.threadId] || []) : []
                    extraHeight: 6
                    isBusy: groupCard.isBusy
                    messageData: messageDelegate.modelData
                    objectName: "groupMessageRow"
                    showAuthors: groupCard.showAuthorInfo
                    showRepositoryInfo: false
                    titleLines: groupCard.titleLines
                    width: repoItems.width

                    onClosePopout: groupCard.closePopout()
                    onMarkDone: function (threadId) {
                        groupCard.markThreadDone(threadId);
                    }
                    onMarkRead: function (threadId) {
                        groupCard.markThreadRead(threadId);
                    }
                    onMarkReadAfterOpen: function (threadId) {
                        groupCard.markThreadReadAfterOpen(threadId);
                    }
                    onMarkUnread: function (threadId) {
                        groupCard.markThreadUnread(threadId);
                    }
                    onRequestAuthors: function (threadId, subjectApiUrl, subjectType) {
                        groupCard.requestThreadAuthors(threadId, subjectApiUrl, subjectType);
                    }
                }
            }
        }
    }
}
