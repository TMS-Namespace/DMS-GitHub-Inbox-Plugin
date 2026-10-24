// RepoGroupingGroup.qml - contract for one repository grouping in the popout.

import QtQuick

QtObject {
    property var allItems: []
    property var items: []
    property string repoAvatarUrl: ""
    property string repoOwnerLogin: ""
    property string repository: ""
    property int unreadCount: 0
}
