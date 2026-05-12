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
            property string login: ""
            property string localPath: ""
            property string remoteUrl: ""
            stdout: SplitParser { onRead: function(line) {} }
            stderr: SplitParser { onRead: function(line) {} }
            onExited: function(exitCode) {
                if (exitCode === 0 && login)
                    worker._onAvatarDlDone(login, localPath)
                else if (login)
                    worker._onAvatarDlFailed(login, localPath)
                var active = worker._cloneMap(worker._avatarActiveLogins)
                delete active[login]
                worker._avatarActiveLogins = active
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
        var nextQueue = _avatarQueue.slice(0)
        var started = 0

        while (_avatarInFlight < maxConcurrent && nextQueue.length > 0) {
            var item = nextQueue.shift()
            if (!item || !item.login || avatarLocalPaths.hasOwnProperty(item.login)
                    || _avatarActiveLogins[item.login] || _avatarFailedLogins[item.login])
                continue

            var active = _cloneMap(_avatarActiveLogins)
            active[item.login] = true
            _avatarActiveLogins = active
            _avatarInFlight++

            var localPath = cacheDir + "/" + GitHubConstants.cacheAvatarsSubdirectory + "/" + item.login + ".png"

            var proc = avatarDlComponent.createObject(worker, {
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
            proc.running = true
            started++
        }

        _avatarQueue = nextQueue
        _profile("_processAvatarQueue", profileStart,
                 "started=" + started + " inFlight=" + _avatarInFlight + " queue=" + _avatarQueue.length)
    }

    function _onAvatarDlDone(login, localPath) {
        var nextPaths = _cloneMap(avatarLocalPaths)
        nextPaths[login] = "file://" + localPath
        avatarLocalPaths = nextPaths
        avatarDownloaded(login, "file://" + localPath, nextPaths)
    }

    function _onAvatarDlFailed(login, localPath) {
        var failed = _cloneMap(_avatarFailedLogins)
        failed[login] = true
        _avatarFailedLogins = failed

        if (localPath) {
            var proc = removeFileComponent.createObject(worker)
            proc.command = ["rm", "-f", localPath]
            proc.running = true
        }
    }

    function _cloneMap(source) {
        var copy = {}
        for (var key in source)
            copy[key] = source[key]
        return copy
    }
}
