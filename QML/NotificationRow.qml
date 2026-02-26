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
    property var authors: []

    signal markRead(string threadId)
    signal markUnread(string threadId)
    signal markDone(string threadId)
    signal requestAuthors(string threadId, string subjectApiUrl, string subjectType)

    property string threadId: notificationData.threadId || ""
    property bool unread: notificationData.unread || false
    property string title: notificationData.title || "(untitled)"
    property string subjectType: notificationData.subjectType || "Notification"
    property string subjectApiUrl: notificationData.subjectApiUrl || ""
    property string reason: GitHub.reasonLabel(notificationData.reason)
    property string updatedAt: notificationData.updatedAt || ""
    property string webUrl: notificationData.webUrl || ""
    property string updatedText: GitHub.relativeTimeFromIso(updatedAt)
    property string subjectIcon: GitHub.subjectIconName(subjectType)
    property bool authorRequestSent: false

    property var resolvedAuthors: authors || []

    property var limitedAuthors: {
        var list = resolvedAuthors || []
        if (list.length <= 3)
            return list
        return list.slice(0, 3)
    }

    property int authorRowHeight: 22
    property int authorColumnHeight: Math.max(0, limitedAuthors.length * authorRowHeight)
    property int contentMinHeight: 40 + (Math.max(1, titleLines) * 16)
    property int rowHeight: Math.max(contentMinHeight, authorColumnHeight + 8)

    function openAuthorProfile(url) {
        if (url)
            Qt.openUrlExternally(url)
    }

    function authorDisplayName(author) {
        if (!author)
            return "unknown"
        var display = String(author.login || "").trim()
        if (display)
            return display
        var profile = String(author.htmlUrl || "").trim()
        if (!profile)
            return "unknown"
        var slash = profile.lastIndexOf("/")
        if (slash < 0 || slash + 1 >= profile.length)
            return "unknown"
        return profile.substring(slash + 1)
    }

    function authorProfile(author) {
        if (!author)
            return ""
        if (author.htmlUrl)
            return author.htmlUrl
        var login = String(author.login || "").trim()
        return login ? ("https://github.com/" + encodeURIComponent(login)) : ""
    }

    function avatarSource(author) {
        if (!author)
            return ""
        var avatarUrl = String(author.avatarUrl || author.avatar_url || "").trim()
        if (avatarUrl)
            return avatarUrl
        var login = String(author.login || "").trim()
        if (!login)
            return ""
        return "https://github.com/" + encodeURIComponent(login) + ".png?size=80"
    }

    function requestAuthorsIfNeeded() {
        if (authorRequestSent)
            return
        if (!threadId || !subjectApiUrl)
            return
        authorRequestSent = true
        requestAuthors(threadId, subjectApiUrl, subjectType)
    }

    Component.onCompleted: requestAuthorsIfNeeded()

    onThreadIdChanged: {
        authorRequestSent = false
        requestAuthorsIfNeeded()
    }

    onSubjectApiUrlChanged: {
        authorRequestSent = false
        requestAuthorsIfNeeded()
    }

    height: Math.max(72, rowHeight)

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
            width: 30
            height: parent.height

            Rectangle {
                width: 26
                height: 24
                radius: 13
                anchors.top: parent.top
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.22)

                DankIcon {
                    anchors.centerIn: parent
                    name: row.subjectIcon
                    size: 17
                    color: row.unread ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }

        Item {
            id: bodySlot
            width: parent.width - iconSlot.width - Theme.spacingS
            height: parent.height

            Row {
                anchors.fill: parent
                spacing: Theme.spacingS

                Column {
                    id: mainInfo
                    width: Math.max(120, Math.floor(bodySlot.width * 0.75))
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
                        width: parent.width
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
                            elide: Text.ElideRight
                        }
                    }
                }

                Item {
                    id: authorInfo
                    width: Math.max(72, bodySlot.width - mainInfo.width - Theme.spacingS)
                    height: parent.height
                    visible: row.limitedAuthors.length > 0

                    Column {
                        id: authorColumn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 2

                        Repeater {
                            model: row.limitedAuthors

                            delegate: Item {
                                required property var modelData
                                width: authorInfo.width
                                height: row.authorRowHeight

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    Item {
                                        id: avatarHost
                                        width: 24
                                        height: 24

                                        Image {
                                            id: avatarImage
                                            source: row.avatarSource(modelData)
                                            asynchronous: true
                                            cache: true
                                            visible: false
                                            onStatusChanged: avatarCanvas.requestPaint()
                                            onSourceChanged: avatarCanvas.requestPaint()
                                        }

                                        Canvas {
                                            id: avatarCanvas
                                            anchors.fill: parent
                                            antialiasing: true
                                            renderTarget: Canvas.Image

                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.save()
                                                ctx.beginPath()
                                                ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, 0, Math.PI * 2, false)
                                                ctx.closePath()
                                                ctx.clip()

                                                if (avatarImage.status === Image.Ready)
                                                    ctx.drawImage(avatarImage, 0, 0, width, height)
                                                else {
                                                    ctx.fillStyle = Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 1)
                                                    ctx.fillRect(0, 0, width, height)
                                                }

                                                ctx.restore()
                                            }
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "person"
                                            size: 12
                                            color: Theme.surfaceVariantText
                                            visible: avatarImage.status !== Image.Ready
                                        }

                                        Component.onCompleted: avatarCanvas.requestPaint()
                                    }

                                    StyledText {
                                        width: Math.max(28, authorInfo.width - avatarHost.width - Theme.spacingXS)
                                        text: row.authorDisplayName(modelData)
                                        font.pixelSize: 11
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: row.openAuthorProfile(row.authorProfile(modelData))
                                }
                            }
                        }
                    }
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
