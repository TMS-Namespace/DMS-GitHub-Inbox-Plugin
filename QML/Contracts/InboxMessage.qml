// InboxMessage.qml - contract for a GitHub notification row.

import QtQuick

QtObject {
    id: model

    property string threadId: ""
    property bool unread: false
    property string reason: ""
    property bool participated: false
    property string updatedAt: ""
    property string repository: ""
    property string repositoryUrl: ""
    property string repositoryOwnerLogin: ""
    property string repositoryOwnerAvatarUrl: ""
    property string subjectType: "Message"
    property string title: "(untitled)"
    property string subjectApiUrl: ""
    property string webUrl: ""

    function readFromObject(value) {
        var source = value || ({})
        threadId = String(source.threadId || "")
        unread = !!source.unread
        reason = String(source.reason || "")
        participated = !!source.participated
        updatedAt = String(source.updatedAt || "")
        repository = String(source.repository || "")
        repositoryUrl = String(source.repositoryUrl || "")
        repositoryOwnerLogin = String(source.repositoryOwnerLogin || "")
        repositoryOwnerAvatarUrl = String(source.repositoryOwnerAvatarUrl || "")
        subjectType = String(source.subjectType || "Message")
        title = String(source.title || "(untitled)")
        subjectApiUrl = String(source.subjectApiUrl || "")
        webUrl = String(source.webUrl || "")
    }

    function toObject() {
        return {
            threadId: threadId,
            unread: unread,
            reason: reason,
            participated: participated,
            updatedAt: updatedAt,
            repository: repository,
            repositoryUrl: repositoryUrl,
            repositoryOwnerLogin: repositoryOwnerLogin,
            repositoryOwnerAvatarUrl: repositoryOwnerAvatarUrl,
            subjectType: subjectType,
            title: title,
            subjectApiUrl: subjectApiUrl,
            webUrl: webUrl
        }
    }
}
