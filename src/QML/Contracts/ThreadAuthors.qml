// ThreadAuthors.qml - contract for author metadata for one notification thread.

import QtQuick

QtObject {
    property var authors: []
    property string fetchedAtUpdatedAt: ""
    property string threadId: ""
}
