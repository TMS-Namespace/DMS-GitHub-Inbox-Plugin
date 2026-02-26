// NotificationRow.qml - Single GitHub notification row for popout list

import QtQuick
import qs.Common
import qs.Widgets
import "../JS/GitHubHelpers.js" as GitHub

Item {
    id: row

    property var notificationData: ({})
    property bool isBusy: false
    property int titleLines: 2

    signal markRead(string threadId)
    signal markUnread(string threadId)
    signal markDone(string threadId)

    property string threadId: notificationData.threadId || ""
    property bool unread: notificationData.unread || false
    property string title: notificationData.title || "(untitled)"
    property string subjectType: notificationData.subjectType || "Notification"
    property string reason: GitHub.reasonLabel(notificationData.reason)
    property string updatedAt: notificationData.updatedAt || ""
    property string webUrl: notificationData.webUrl || ""
    property string updatedText: GitHub.relativeTimeFromIso(updatedAt)
    property string subjectIcon: GitHub.subjectIconName(subjectType)
    property int rowHeight: 40 + (Math.max(1, titleLines) * 16)

    height: Math.max(64, rowHeight)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: row.unread
               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
               : Theme.surfaceContainer
        border.color: row.unread
                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                      : Theme.outlineVariant
        border.width: 1
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: webUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (webUrl)
                Qt.openUrlExternally(webUrl)
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Item {
            id: iconSlot
            width: 26
            height: parent.height

            Rectangle {
                width: 24
                height: 22
                radius: 12
                anchors.top: parent.top
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.22)

                DankIcon {
                    anchors.centerIn: parent
                    name: row.subjectIcon
                    size: 16
                    color: row.unread ? Theme.primary : Theme.surfaceVariantText
                }
            }

        }

        Column {
            id: textColumn
            width: parent.width - iconSlot.width - Theme.spacingS * 2
            anchors.top: parent.top
            spacing: 3

            StyledText {
                width: parent.width
                text: row.title
                font.pixelSize: Theme.fontSizeSmall
                font.weight: row.unread ? Font.DemiBold : Font.Medium
                color: Theme.surfaceText
                wrapMode: Text.Wrap
                maximumLineCount: Math.max(1, row.titleLines)
                elide: Text.ElideRight
            }

            Row {
                spacing: Theme.spacingXS

                StyledText {
                    text: row.subjectType
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: "\u2022"
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: row.reason
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: "\u2022"
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: row.updatedText
                    font.pixelSize: 10
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    // -- Hover actions --------------------------------------------------------
    Item {
        id: actionsHost
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 4
        anchors.topMargin: 4
        width: 74
        height: 24
        z: 10

        MouseArea {
            id: actionsHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Row {
            id: actionButtons
            spacing: 4
            visible: rowArea.containsMouse
                     || actionsHoverArea.containsMouse
                     || openArea.containsMouse
                     || readToggleArea.containsMouse
                     || doneArea.containsMouse
            opacity: visible ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 100 }
            }

            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)

                MouseArea {
                    id: openArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: webUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: webUrl !== ""
                    onClicked: Qt.openUrlExternally(webUrl)
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "open_in_new"
                    size: 13
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)

                MouseArea {
                    id: readToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !row.isBusy && row.threadId !== ""
                    onClicked: {
                        if (row.unread)
                            row.markRead(row.threadId)
                        else
                            row.markUnread(row.threadId)
                    }
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: row.unread ? "mark_email_read" : "mark_email_unread"
                    size: 13
                    color: readToggleArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.9)

                MouseArea {
                    id: doneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !row.isBusy && row.threadId !== ""
                    onClicked: row.markDone(row.threadId)
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "done"
                    size: 13
                    color: doneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }
    }
}
