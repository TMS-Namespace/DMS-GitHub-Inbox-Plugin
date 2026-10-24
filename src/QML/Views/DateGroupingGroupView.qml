// DateGroupingGroupView.qml - expandable message group for one date bucket.

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
    property bool headerActionsHovered: dateHeaderArea.containsMouse || dateReadArea.containsMouse || dateDoneArea.containsMouse
    property bool isBusy: false
    property bool showAuthorInfo: true
    property int titleLines: GitHubConstants.defaultTitleLines

    signal closePopout
    signal markGroupDone(var items)
    signal markGroupRead(var items)
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
            id: dateHeader

            height: Theme.fontSizeMedium + GitHubConstants.popoutRepoHeaderHeightDelta
            width: parent.width

            MouseArea {
                id: dateHeaderArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: groupCard.toggleExpanded()
            }
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS + GitHubConstants.popoutGroupHeaderLeadingInsetDelta
                anchors.right: dateMeta.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceText
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                text: groupCard.groupData.label || ""
            }
            Row {
                id: dateMeta

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Rectangle {
                    color: groupCard.isBusy ? Theme.withAlpha(Theme.surfaceVariant, 0.55) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                    height: GitHubConstants.popoutRepoDoneButtonSizePx
                    opacity: groupCard.hasUnreadActionItems && groupCard.headerActionsHovered ? 1 : 0
                    radius: Math.max(0, Math.min(GitHubConstants.popoutRepoDoneButtonSizePx / 2, Theme.cornerRadius + GitHubConstants.popoutRepoDoneButtonRadiusDelta))
                    visible: groupCard.expanded && groupCard.hasActionItems
                    width: GitHubConstants.popoutRepoDoneButtonSizePx
                    z: 2

                    MouseArea {
                        id: dateReadArea

                        anchors.fill: parent
                        cursorShape: groupCard.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        hoverEnabled: true

                        onClicked: {
                            if (!groupCard.isBusy)
                                groupCard.markGroupRead(groupCard.actionItems());
                        }
                    }
                    DIcon {
                        anchors.centerIn: parent
                        color: groupCard.isBusy ? Theme.withAlpha(Theme.surfaceVariantText, 0.55) : (dateReadArea.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                        name: "mark_email_read"
                        size: GitHubConstants.popoutRepoDoneIconSizePx
                    }
                }
                Rectangle {
                    color: groupCard.isBusy ? Theme.withAlpha(Theme.surfaceVariant, 0.55) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                    height: GitHubConstants.popoutRepoDoneButtonSizePx
                    opacity: groupCard.headerActionsHovered ? 1 : 0
                    radius: Math.max(0, Math.min(GitHubConstants.popoutRepoDoneButtonSizePx / 2, Theme.cornerRadius + GitHubConstants.popoutRepoDoneButtonRadiusDelta))
                    visible: groupCard.expanded && groupCard.hasActionItems
                    width: GitHubConstants.popoutRepoDoneButtonSizePx
                    z: 2

                    MouseArea {
                        id: dateDoneArea

                        anchors.fill: parent
                        cursorShape: groupCard.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        hoverEnabled: true

                        onClicked: {
                            if (!groupCard.isBusy)
                                groupCard.markGroupDone(groupCard.actionItems());
                        }
                    }
                    DIcon {
                        anchors.centerIn: parent
                        color: groupCard.isBusy ? Theme.withAlpha(Theme.surfaceVariantText, 0.55) : (dateDoneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                        name: "done"
                        size: GitHubConstants.popoutRepoDoneIconSizePx
                    }
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
            Rectangle {
                anchors.bottom: dateMeta.top
                anchors.bottomMargin: Theme.spacingXS
                anchors.right: dateMeta.right
                border.color: Theme.outlineMedium
                border.width: 1
                color: Theme.surfaceContainerHighest
                height: dateActionTooltipText.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                visible: groupCard.isBusy && groupCard.expanded && (dateReadArea.containsMouse || dateDoneArea.containsMouse)
                width: dateActionTooltipText.implicitWidth + Theme.spacingS * 2
                z: 20

                StyledText {
                    id: dateActionTooltipText

                    anchors.centerIn: parent
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall + GitHubConstants.messageMetadataFontSizeDelta
                    text: "Not available during refresh"
                }
            }
        }
        Column {
            id: dateItems

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
                    isBusy: groupCard.isBusy
                    messageData: messageDelegate.modelData
                    objectName: "groupMessageRow"
                    showAuthors: groupCard.showAuthorInfo
                    showRepositoryInfo: true
                    titleLines: groupCard.titleLines
                    width: dateItems.width

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
