// ThreadAuthors.qml - contract for author metadata for one notification thread.

import QtQuick

QtObject {
    id: model

    property string threadId: ""
    property var authors: []
    property string fetchedAtUpdatedAt: ""

    function readFromObject(value) {
        var source = value || ({})
        threadId = String(source.threadId || "")
        authors = source.authors || []
        fetchedAtUpdatedAt = String(source.fetchedAtUpdatedAt || "")
    }

    function toObject() {
        return {
            threadId: threadId,
            authors: authors || [],
            fetchedAtUpdatedAt: fetchedAtUpdatedAt
        }
    }
}
