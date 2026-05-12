// InboxGroup.qml - contract for one repository group in the popout.

import QtQuick

QtObject {
    id: model

    property string repository: ""
    property int unreadCount: 0
    property string repoOwnerLogin: ""
    property string repoAvatarUrl: ""
    property var items: []

    function readFromObject(value) {
        var source = value || ({})
        repository = String(source.repository || "")
        unreadCount = parseInt(source.unreadCount || 0)
        if (isNaN(unreadCount))
            unreadCount = 0
        repoOwnerLogin = String(source.repoOwnerLogin || "")
        repoAvatarUrl = String(source.repoAvatarUrl || "")
        items = source.items || []
    }

    function toObject() {
        return {
            repository: repository,
            unreadCount: unreadCount,
            repoOwnerLogin: repoOwnerLogin,
            repoAvatarUrl: repoAvatarUrl,
            items: items || []
        }
    }
}
