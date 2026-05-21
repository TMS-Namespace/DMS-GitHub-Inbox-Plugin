// AvatarCacheEntry.qml - contract for one cached avatar file entry.

import QtQuick

QtObject {
    id: model

    property string login: ""
    property string localFile: ""
    property string localUrl: ""

    function readFromObject(value, entryLogin, cacheDir, avatarSubdirectory) {
        var source = value || ({})
        login = String(entryLogin || source.login || "")
        localFile = String(source.localFile || "")
        localUrl = localFile && cacheDir && avatarSubdirectory
                ? ("file://" + cacheDir + "/" + avatarSubdirectory + "/" + localFile)
                : String(source.localUrl || "")
    }

    function toObject() {
        return {
            localFile: localFile
        }
    }
}
