// AvatarBackgroundWorker.qml - background avatar download queue.

import QtQuick
import ".."

Item {
    id: worker

    property var _avatarActiveLogins: ({})
    property var _avatarFailedLogins: ({})
    property int _avatarInFlight: 0
    property var _avatarQueue: []
    property int _generation: 0
    property var avatarLocalPaths: ({})
    property bool cacheReady: false
    readonly property bool isBusy: _avatarInFlight > 0 || _avatarQueue.length > 0
    readonly property var providerApi: GitHubManager.getProviderApi(GitHubManager.providerTypes[0])

    signal avatarDownloadRequested(string login, string remoteUrl, int generation)
    signal avatarDownloaded(string login, string localUrl, var avatarLocalPaths)

    // Combine queued, active and failed logins before selecting more downloads.
    function _blockedAvatarLogins() {
        let blocked = {};
        for (let login in avatarLocalPaths)
            blocked[login] = true;
        for (let activeLogin in _avatarActiveLogins)
            blocked[activeLogin] = true;
        for (let failedLogin in _avatarFailedLogins)
            blocked[failedLogin] = true;
        return blocked;
    }
    // Promote a completed download to the local cache and release its queue slot.
    function _onAvatarDlDone(login, localUrl) {
        avatarLocalPaths[login] = localUrl;
        avatarDownloaded(login, localUrl, avatarLocalPaths);
    }
    // Keep a failed download from being immediately requeued in the same generation.
    function _onAvatarDlFailed(login) {
        _avatarFailedLogins[login] = true;
    }
    // Start at most the configured number of downloads concurrently.
    function _processAvatarQueue() {
        let profileStart = Date.now();
        if (_avatarQueue.length === 0)
            return;
        let maxConcurrent = Math.max(1, GitHubConstants.maxConcurrentAvatarDownloads);
        let started = 0;
        let queueOffset = 0;

        while (_avatarInFlight < maxConcurrent && queueOffset < _avatarQueue.length) {
            let item = _avatarQueue[queueOffset];
            queueOffset++;
            if (!item || !item.login || avatarLocalPaths.hasOwnProperty(item.login) || _avatarActiveLogins[item.login] || _avatarFailedLogins[item.login])
                continue;
            _avatarActiveLogins[item.login] = true;
            _avatarInFlight++;

            ApiCallStats.recordCalls(1);
            avatarDownloadRequested(item.login, item.remoteUrl, _generation);
            started++;
        }

        if (queueOffset > 0)
            _avatarQueue = _avatarQueue.slice(queueOffset);
        _profile("_processAvatarQueue", profileStart, "started=" + started + " inFlight=" + _avatarInFlight + " queue=" + _avatarQueue.length);
    }
    // Measure this operation through the shared profiling gate.
    function _profile(label, startMs, details) {
        let duration = Date.now() - startMs;
        PluginLogger.profile("AvatarBackgroundWorker", label, duration, details);
    }
    // Apply the same bounds and deduplication to a group of download candidates.
    function batchQueueAvatarDownloads(items) {
        let profileStart = Date.now();
        if (!cacheReady || !providerApi || !items || items.length === 0)
            return;
        let nextQueue = providerApi.appendBoundedAvatarRequests(_avatarQueue, items, _blockedAvatarLogins(), GitHubConstants.maxAvatarQueueLength);
        if (nextQueue.length === _avatarQueue.length)
            return;
        _avatarQueue = nextQueue;
        _profile("batchQueueAvatarDownloads", profileStart, "items=" + items.length + " queue=" + _avatarQueue.length);
        _processAvatarQueue();
    }
    // Release the active slot and update local resources only after download completion.
    function onAvatarDownloadFinished(login, localUrl, generation, success) {
        if (generation === _generation) {
            if (success)
                _onAvatarDlDone(login, localUrl);
            else
                _onAvatarDlFailed(login);
            delete _avatarActiveLogins[login];
            _avatarInFlight = Math.max(0, _avatarInFlight - 1);
            _processAvatarQueue();
        }
    }
    // Reject duplicate or blocked logins before claiming a concurrency slot.
    function queueAvatarDownload(login, remoteUrl) {
        let profileStart = Date.now();
        if (!cacheReady || !providerApi || !providerApi.isSafeLogin(login) || !providerApi.isAllowedAvatarUrl(remoteUrl)) {
            PluginLogger.error("avatar", "Rejected an invalid avatar download request");
            return;
        }
        let nextQueue = providerApi.appendBoundedAvatarRequests(_avatarQueue, [
            {
                login: login,
                remoteUrl: remoteUrl
            }
        ], _blockedAvatarLogins(), GitHubConstants.maxAvatarQueueLength);
        if (nextQueue.length === _avatarQueue.length)
            return;
        _avatarQueue = nextQueue;
        _profile("queueAvatarDownload", profileStart, "queue=" + _avatarQueue.length);
        _processAvatarQueue();
    }
    // Invalidate active download results and clear queued, active, failed and local-avatar maps.
    function reset() {
        _generation = _generation + 1;
        _avatarQueue = [];
        _avatarInFlight = 0;
        _avatarActiveLogins = ({});
        _avatarFailedLogins = ({});
        avatarLocalPaths = ({});
    }
    // Restore the known local resource map before scheduling missing downloads.
    function setAvatarLocalPaths(paths) {
        avatarLocalPaths = paths || ({});
    }

    visible: false
}
