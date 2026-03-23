// InboxMessageGroup.qml - Grouped inbox message list card for a single repository

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

    signal toggleExpanded()
    signal markRepoDone()
    signal markThreadRead(string threadId)
    signal markThreadUnread(string threadId)
    signal markThreadDone(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)
    signal closePopout()

    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.outlineVariant
    implicitHeight: groupColumn.implicitHeight + Theme.spacingS * 2

    Column {
        id: groupColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Item {
            id: repoHeader
            width: parent.width
            height: Constants.popoutRepoHeaderHeightPx

            MouseArea {
                id: repoHeaderArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: groupCard.toggleExpanded()
            }

            Row {
                anchors.left: parent.left
                anchors.right: repoMeta.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Item {
                    width: Constants.popoutRepoAvatarSizePx
                    height: Constants.popoutRepoAvatarSizePx
                    anchors.verticalCenter: parent.verticalCenter

                    RoundedAvatar {
                        anchors.fill: parent
                        source: groupCard.groupData.repoAvatarUrl || ""
                        fallbackIcon: "folder"
                        fallbackIconSize: Constants.popoutRepoAvatarFallbackIconSizePx
                    }
                }

                StyledText {
                    width: parent.width - 30
                    text: groupCard.groupData.repository || ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                id: repoMeta
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Rectangle {
                    width: Constants.popoutRepoDoneButtonSizePx
                    height: Constants.popoutRepoDoneButtonSizePx
                    radius: Constants.popoutRepoDoneButtonRadiusPx
                    visible: groupCard.groupData.items && groupCard.groupData.items.length > 0
                             && (repoHeaderArea.containsMouse || repoDoneArea.containsMouse)
                    color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)
                    z: 2

                    MouseArea {
                        id: repoDoneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: groupCard.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !groupCard.isBusy
                        onClicked: groupCard.markRepoDone()
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "done"
                        size: Constants.popoutRepoDoneIconSizePx
                        color: repoDoneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                Rectangle {
                    visible: groupCard.groupData.items && groupCard.groupData.items.length > 0
                    height: Constants.popoutRepoCountBadgeHeightPx
                    radius: Constants.popoutRepoCountBadgeRadiusPx
                    width: groupCountText.implicitWidth + Theme.spacingS
                    color: (groupCard.groupData.unreadCount || 0) > 0
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.popoutRepoCountBadgeUnreadOpacity)
                           : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, Constants.popoutRepoCountBadgeReadOpacity)

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
                        font.pixelSize: Constants.popoutRepoCountFontSizePx
                        font.weight: Font.Medium
                        color: (groupCard.groupData.unreadCount || 0) > 0
                               ? Theme.primary
                               : Theme.surfaceVariantText
                    }
                }

                DankIcon {
                    name: "expand_more"
                    size: Constants.popoutRepoExpandIconSizePx
                    color: Theme.surfaceVariantText
                    rotation: groupCard.expanded ? 0 : -90

                    Behavior on rotation {
                        NumberAnimation { duration: Constants.popoutRepoExpandRotationDurationMs }
                    }
                }
            }
        }

        Column {
            id: repoItems
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
