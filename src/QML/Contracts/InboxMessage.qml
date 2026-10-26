// InboxMessage.qml - contract for a GitHub notification row.

import QtQuick

QtObject {
    property bool participated: false
    property string reason: ""
    property string repository: ""
    property string repositoryOwnerAvatarUrl: ""
    property string repositoryOwnerLogin: ""
    property string repositoryUrl: ""
    property string subjectApiUrl: ""
    property string subjectReference: ""
    property string subjectType: "Message"
    property string threadId: ""
    property string title: "(untitled)"
    property bool unread: false
    property string updatedAt: ""
    property double updatedAtMs: 0
    property string webUrl: ""
    property bool webUrlResolved: false
}
