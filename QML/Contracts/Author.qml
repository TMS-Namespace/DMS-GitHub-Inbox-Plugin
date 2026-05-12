// Author.qml - contract for a GitHub user/organization shown on a thread.

import QtQuick

QtObject {
    id: model

    property string login: ""
    property string avatarUrl: ""
    property string htmlUrl: ""

    function readFromObject(value) {
        var source = value || ({})
        login = String(source.login || "")
        avatarUrl = String(source.avatarUrl || source.avatar_url || "")
        htmlUrl = String(source.htmlUrl || source.html_url || "")
    }

    function toObject() {
        return {
            login: login,
            avatarUrl: avatarUrl,
            htmlUrl: htmlUrl
        }
    }
}
