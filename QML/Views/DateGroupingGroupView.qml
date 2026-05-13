// DateGroupingGroupView.qml - expandable message group for one date bucket.

import QtQuick
import qs.Common
import qs.Widgets
import ".."

Rectangle {
    id: groupCard

    property var groupData: ({})
    property bool expanded: false
    property var authorsByThread: ({})
    property bool showAuthorInfo: true
    property bool isBusy: false
    property int titleLines: 2
    property bool headerActionsHovered: dateHeaderArea.containsMouse
                                        || dateReadArea.containsMouse
                                        || dateDoneArea.containsMouse

    signal toggleExpanded()
    signal markGroupRead(var items)
    signal markGroupDone(var items)
    signal markThreadRead(string threadId)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()

    radius: Theme.cornerRadius
    color: Theme.nestedSurface
    border.width: 1
    border.color: Theme.outlineMedium
    implicitHeight: groupColumn.implicitHeight + Theme.spacingS * 2

    Column {
        id: groupColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Item {
            id: dateHeader
            width: parent.width
            height: GitHubConstants.popoutRepoHeaderHeightPx

            MouseArea {
                id: dateHeaderArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: groupCard.toggleExpanded()
            }

            StyledText {
                anchors.left: parent.left
                anchors.right: dateMeta.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: groupCard.groupData.label || ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            Row {
                id: dateMeta
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Rectangle {
                    width: GitHubConstants.popoutRepoDoneButtonSizePx
                    height: GitHubConstants.popoutRepoDoneButtonSizePx
                    radius: GitHubConstants.popoutRepoDoneButtonRadiusPx
                    visible: groupCard.groupData.items && groupCard.groupData.items.length > 0
                             && (groupCard.groupData.unreadCount || 0) > 0
                             && groupCard.headerActionsHovered
                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                    z: 2

                    MouseArea {
                        id: dateReadArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: groupCard.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !groupCard.isBusy
                        onClicked: groupCard.markGroupRead(groupCard.groupData.items || [])
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "mark_email_read"
                        size: GitHubConstants.popoutRepoDoneIconSizePx
                        color: dateReadArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                Rectangle {
                    width: GitHubConstants.popoutRepoDoneButtonSizePx
                    height: GitHubConstants.popoutRepoDoneButtonSizePx
                    radius: GitHubConstants.popoutRepoDoneButtonRadiusPx
                    visible: groupCard.groupData.items && groupCard.groupData.items.length > 0
                             && groupCard.headerActionsHovered
                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                    z: 2

                    MouseArea {
                        id: dateDoneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: groupCard.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !groupCard.isBusy
                        onClicked: groupCard.markGroupDone(groupCard.groupData.items || [])
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "done"
                        size: GitHubConstants.popoutRepoDoneIconSizePx
                        color: dateDoneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                Rectangle {
                    visible: groupCard.groupData.items && groupCard.groupData.items.length > 0
                    height: GitHubConstants.popoutRepoCountBadgeHeightPx
                    radius: GitHubConstants.popoutRepoCountBadgeRadiusPx
                    width: groupCountText.implicitWidth + Theme.spacingS
                    color: (groupCard.groupData.unreadCount || 0) > 0
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, GitHubConstants.popoutRepoCountBadgeUnreadOpacity)
                           : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, GitHubConstants.popoutRepoCountBadgeReadOpacity)

                    StyledText {
                        id: groupCountText
                        anchors.centerIn: parent
                        text: {
                            var items = (groupCard.groupData.items || [])
                            var unread = groupCard.groupData.unreadCount || 0
                            return unread < items.length
                                   ? (unread + "/" + items.length)
                                   : String(items.length)
                        }
                        font.pixelSize: GitHubConstants.popoutRepoCountFontSizePx
                        font.weight: Font.Medium
                        color: (groupCard.groupData.unreadCount || 0) > 0
                               ? Theme.primary
                               : Theme.surfaceVariantText
                    }
                }

                DankIcon {
                    name: "expand_more"
                    size: GitHubConstants.popoutRepoExpandIconSizePx
                    color: Theme.surfaceVariantText
                    rotation: groupCard.expanded ? 0 : -90

                    Behavior on rotation {
                        NumberAnimation { duration: GitHubConstants.popoutRepoExpandRotationDurationMs }
                    }
                }
            }
        }

        Column {
            id: dateItems
            width: parent.width
            spacing: Theme.spacingXS
            visible: groupCard.expanded
            height: visible ? implicitHeight : 0
            clip: true

            Repeater {
                model: groupCard.groupData.items || []

                delegate: InboxMessageRow {
                    width: parent.width
                    messageData: modelData
                    authors: groupCard.showAuthorInfo ? (groupCard.authorsByThread[modelData.threadId] || []) : []
                    showAuthors: groupCard.showAuthorInfo
                    showRepositoryInfo: true
                    allowAuthorRequests: false
                    isBusy: groupCard.isBusy
                    titleLines: groupCard.titleLines
                    onMarkRead: function(threadId) { groupCard.markThreadRead(threadId) }
                    onMarkUnread: function(threadId) { groupCard.markThreadUnread(threadId) }
                    onMarkDone: function(threadId) { groupCard.markThreadDone(threadId) }
                    onRequestAuthors: function(threadId, subjectApiUrl, subjectType) {
                        groupCard.requestThreadAuthors(threadId, subjectApiUrl, subjectType)
                    }
                    onClosePopout: groupCard.closePopout()
                }
            }
        }
    }
}
