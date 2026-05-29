// InboxMessage.qml - contract for a GitHub notification row.

import QtQuick

QtObject {
    id: model

    property string threadId: ""
    property bool unread: false
    property string reason: ""
    property bool participated: false
    property string updatedAt: ""
    property double updatedAtMs: 0
    property string repository: ""
    property string repositoryUrl: ""
    property string repositoryOwnerLogin: ""
    property string repositoryOwnerAvatarUrl: ""
    property string subjectType: "Message"
    property string title: "(untitled)"
    property string subjectApiUrl: ""
    property string subjectReference: ""
    property string webUrl: ""
    property bool webUrlResolved: false

    function readFromObject(value) {
        var source = value || ({})
        threadId = String(source.threadId || "")
        unread = !!source.unread
        reason = String(source.reason || "")
        participated = !!source.participated
        updatedAt = String(source.updatedAt || "")
        updatedAtMs = parseFloat(source.updatedAtMs || 0)
        if (isNaN(updatedAtMs))
            updatedAtMs = 0
        repository = String(source.repository || "")
        repositoryUrl = String(source.repositoryUrl || "")
        repositoryOwnerLogin = String(source.repositoryOwnerLogin || "")
        repositoryOwnerAvatarUrl = String(source.repositoryOwnerAvatarUrl || "")
        subjectType = String(source.subjectType || "Message")
        title = String(source.title || "(untitled)")
        subjectApiUrl = String(source.subjectApiUrl || "")
        subjectReference = String(source.subjectReference || "")
        webUrl = String(source.webUrl || "")
        webUrlResolved = !!source.webUrlResolved
    }

    function toObject() {
        return {
            threadId: threadId,
            unread: unread,
            reason: reason,
            participated: participated,
            updatedAt: updatedAt,
            updatedAtMs: updatedAtMs,
            repository: repository,
            repositoryUrl: repositoryUrl,
            repositoryOwnerLogin: repositoryOwnerLogin,
            repositoryOwnerAvatarUrl: repositoryOwnerAvatarUrl,
            subjectType: subjectType,
            title: title,
            subjectApiUrl: subjectApiUrl,
            subjectReference: subjectReference,
            webUrl: webUrl,
            webUrlResolved: webUrlResolved
        }
    }
}
