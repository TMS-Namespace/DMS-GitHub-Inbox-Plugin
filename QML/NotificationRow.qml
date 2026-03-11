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
    property bool showAuthors: true

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
        if (list.length <= Constants.maxAuthorsDisplayedPerNotification)
            return list
        return list.slice(0, Constants.maxAuthorsDisplayedPerNotification)
    }

    property int authorRowHeight: Constants.notificationAuthorRowHeightPx
    property int authorColumnHeight: showAuthors ? Math.max(0, limitedAuthors.length * authorRowHeight) : 0
    property int contentMinHeight: Constants.notificationRowContentMinHeightPx + (Math.max(1, titleLines) * Constants.notificationRowTitleLineHeightPx)
    property int rowHeight: Math.max(contentMinHeight, authorColumnHeight + Constants.notificationRowAuthorColumnPaddingPx)

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
        return Constants.githubWebBaseUrl + "/" + encodeURIComponent(login) + ".png?size=128"
    }

    function requestAuthorsIfNeeded() {
        // Authors are pre-fetched during refresh in Widget.qml.
    }

    height: Math.max(Constants.notificationRowMinHeightPx, rowHeight)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: row.unread
               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.notificationRowUnreadBackgroundOpacity)
               : Theme.surfaceContainer
        border.color: row.unread
                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Constants.notificationRowUnreadBorderOpacity)
                      : Theme.outlineVariant
        border.width: Constants.notificationRowBorderWidthPx
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
            width: Constants.notificationIconSlotWidthPx
            height: parent.height

            Rectangle {
                width: Constants.notificationIconBadgeWidthPx
                height: Constants.notificationIconBadgeHeightPx
                radius: Constants.notificationIconBadgeRadiusPx
                anchors.top: parent.top
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, Constants.notificationIconBadgeBackgroundOpacity)

                DankIcon {
                    anchors.centerIn: parent
                    name: row.subjectIcon
                    size: Constants.notificationSubjectIconSizePx
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
                    width: (showAuthors && row.limitedAuthors.length > 0)
                           ? Math.max(Constants.notificationMainInfoMinWidthPx, Math.floor(bodySlot.width * Constants.notificationMainInfoWidthRatio))
                           : bodySlot.width
                    anchors.top: parent.top
                    spacing: Constants.notificationMainInfoColumnSpacingPx

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
                            font.pixelSize: Constants.notificationMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "\u2022"
                            font.pixelSize: Constants.notificationMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: row.reason
                            font.pixelSize: Constants.notificationMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: "\u2022"
                            font.pixelSize: Constants.notificationMetadataFontSizePx
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: row.updatedText
                            font.pixelSize: Constants.notificationMetadataFontSizePx
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }
                }

                Item {
                    id: authorInfo
                    width: Math.max(Constants.notificationAuthorColumnMinWidthPx, bodySlot.width - mainInfo.width - Theme.spacingS)
                    height: parent.height
                    visible: row.showAuthors && row.limitedAuthors.length > 0

                    Column {
                        id: authorColumn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Constants.notificationAuthorColumnItemSpacingPx

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
                                        width: Constants.authorAvatarSizePx
                                        height: Constants.authorAvatarSizePx

                                        RoundedAvatar {
                                            anchors.fill: parent
                                            source: row.avatarSource(modelData)
                                            fallbackIcon: "person"
                                            fallbackIconSize: Constants.authorAvatarFallbackIconSizePx
                                        }
                                    }

                                    StyledText {
                                        width: Math.max(Constants.authorNameMinWidthPx, authorInfo.width - avatarHost.width - Theme.spacingXS)
                                        text: row.authorDisplayName(modelData)
                                        font.pixelSize: Constants.authorNameFontSizePx
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        wrapMode: Text.NoWrap
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
        anchors.rightMargin: Constants.notificationActionsHostMarginPx
        anchors.topMargin: Constants.notificationActionsHostMarginPx
        width: Constants.notificationActionsHostWidthPx
        height: Constants.notificationActionsHostHeightPx
        z: 10

        MouseArea {
            id: actionsHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Row {
            id: actionButtons
            spacing: Constants.notificationActionButtonsSpacingPx
            visible: rowArea.containsMouse
                     || actionsHoverArea.containsMouse
                     || openArea.containsMouse
                     || readToggleArea.containsMouse
                     || doneArea.containsMouse
            opacity: visible ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Constants.notificationActionsFadeDurationMs }
            }

            Rectangle {
                width: Constants.notificationActionButtonSizePx
                height: Constants.notificationActionButtonSizePx
                radius: Constants.notificationActionButtonRadiusPx
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.notificationActionButtonBgOpacity)

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
                    size: Constants.notificationActionButtonIconSizePx
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: Constants.notificationActionButtonSizePx
                height: Constants.notificationActionButtonSizePx
                radius: Constants.notificationActionButtonRadiusPx
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.notificationActionButtonBgOpacity)

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
                    size: Constants.notificationActionButtonIconSizePx
                    color: readToggleArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: Constants.notificationActionButtonSizePx
                height: Constants.notificationActionButtonSizePx
                radius: Constants.notificationActionButtonRadiusPx
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, Constants.notificationActionButtonBgOpacity)

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
                    size: Constants.notificationActionButtonIconSizePx
                    color: doneArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                }
            }
        }
    }
}
