// AvatarBackgroundWorker.qml - background avatar download queue.

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: worker
    visible: false

    property string cacheDir: ""
    property var avatarLocalPaths: ({})

    readonly property bool isBusy: _avatarInFlight > 0 || _avatarQueue.length > 0

    property var _avatarQueue: []
    property int _avatarInFlight: 0
    property var _avatarActiveLogins: ({})
    property var _avatarFailedLogins: ({})
    property int _generation: 0

    signal avatarDownloaded(string login, string localUrl, var avatarLocalPaths)

    function _profile(label, startMs, details) {
        if (!GitHubConstants.profileLoggingEnabled)
            return
        var duration = Date.now() - startMs
        if (!GitHubConstants.profileLogAllOperations
                && duration < GitHubConstants.profileSlowOperationThresholdMs)
            return
        var suffix = details ? (" — " + details) : ""
        console.warn("[GitHubInbox PROFILE] AvatarBackgroundWorker." + label
                     + " took " + duration + "ms" + suffix)
    }

    function setAvatarLocalPaths(paths) {
        avatarLocalPaths = paths || ({})
    }

    function reset() {
        _generation = _generation + 1
        _avatarQueue = []
        _avatarInFlight = 0
        _avatarActiveLogins = ({})
        _avatarFailedLogins = ({})
        avatarLocalPaths = ({})
    }

    function queueAvatarDownload(login, remoteUrl) {
        var profileStart = Date.now()
        if (!cacheDir || !login || !remoteUrl)
            return
        if (_avatarFailedLogins[login])
            return
        if (avatarLocalPaths.hasOwnProperty(login))
            return
        if (_avatarActiveLogins[login])
            return

        for (var i = 0; i < _avatarQueue.length; i++) {
            if (_avatarQueue[i].login === login)
                return
        }

        var nextQueue = _avatarQueue.slice(0)
        nextQueue.push({ login: login, remoteUrl: remoteUrl })
        _avatarQueue = nextQueue
        _profile("queueAvatarDownload", profileStart, "queue=" + _avatarQueue.length)
        _processAvatarQueue()
    }

    function batchQueueAvatarDownloads(items) {
        var profileStart = Date.now()
        if (!cacheDir || !items || items.length === 0)
            return

        var existingLogins = {}
        for (var qi = 0; qi < _avatarQueue.length; qi++)
            existingLogins[_avatarQueue[qi].login] = true
        for (var activeLogin in _avatarActiveLogins)
            existingLogins[activeLogin] = true

        var toAdd = []
        for (var i = 0; i < items.length; i++) {
            var login = items[i].login
            var remoteUrl = items[i].remoteUrl
            if (!login || !remoteUrl)
                continue
            if (_avatarFailedLogins[login])
                continue
            if (avatarLocalPaths.hasOwnProperty(login))
                continue
            if (existingLogins[login])
                continue

            existingLogins[login] = true
            toAdd.push({ login: login, remoteUrl: remoteUrl })
        }

        if (toAdd.length === 0)
            return

        var nextQueue = _avatarQueue.slice(0)
        for (var j = 0; j < toAdd.length; j++)
            nextQueue.push(toAdd[j])
        _avatarQueue = nextQueue
        _profile("batchQueueAvatarDownloads", profileStart,
                 "items=" + items.length + " added=" + toAdd.length + " queue=" + _avatarQueue.length)
        _processAvatarQueue()
    }

    Component {
        id: avatarDlComponent
        Process {
            property int generation: 0
            property string login: ""
            property string localPath: ""
            property string remoteUrl: ""
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                if (generation !== worker._generation) {
                    if (localPath)
                        worker._removeLocalFile(localPath)
                    destroy()
                    return
                }

                if (exitCode === 0 && login)
                    worker._onAvatarDlDone(login, localPath)
                else if (login)
                    worker._onAvatarDlFailed(login, localPath)
                delete worker._avatarActiveLogins[login]
                worker._avatarInFlight = Math.max(0, worker._avatarInFlight - 1)
                worker._processAvatarQueue()
                destroy()
            }
        }
    }

    Component {
        id: removeFileComponent
        Process {
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) { destroy() }
        }
    }

    function _processAvatarQueue() {
        var profileStart = Date.now()
        if (_avatarQueue.length === 0)
            return

        var maxConcurrent = Math.max(1, GitHubConstants.maxConcurrentAvatarDownloads)
        var started = 0
        var queueOffset = 0

        while (_avatarInFlight < maxConcurrent && queueOffset < _avatarQueue.length) {
            var item = _avatarQueue[queueOffset]
            queueOffset++
            if (!item || !item.login || avatarLocalPaths.hasOwnProperty(item.login)
                    || _avatarActiveLogins[item.login] || _avatarFailedLogins[item.login])
                continue

            _avatarActiveLogins[item.login] = true
            _avatarInFlight++

            var localPath = cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory + "/" + item.login + ".png"

            var proc = avatarDlComponent.createObject(worker, {
                generation: _generation,
                login: item.login,
                localPath: localPath,
                remoteUrl: item.remoteUrl
            })
            proc.command = [
                "curl", "-f", "-sS", "-L",
                "--connect-timeout", GitHubConstants.avatarDownloadConnectTimeoutSeconds,
                "--max-time", GitHubConstants.avatarDownloadMaxTimeSeconds,
                "-o", localPath,
                item.remoteUrl
            ]
            ApiCallStats.recordCalls(1)
            proc.running = true
            started++
        }

        if (queueOffset > 0)
            _avatarQueue = _avatarQueue.slice(queueOffset)
        _profile("_processAvatarQueue", profileStart,
                 "started=" + started + " inFlight=" + _avatarInFlight + " queue=" + _avatarQueue.length)
    }

    function _onAvatarDlDone(login, localPath) {
        var localUrl = "file://" + localPath
        avatarLocalPaths[login] = localUrl
        avatarDownloaded(login, localUrl, avatarLocalPaths)
    }

    function _onAvatarDlFailed(login, localPath) {
        _avatarFailedLogins[login] = true

        if (localPath) {
            _removeLocalFile(localPath)
        }
    }

    function _removeLocalFile(localPath) {
        var proc = removeFileComponent.createObject(worker)
        proc.command = ["rm", "-f", localPath]
        proc.running = true
    }

}
