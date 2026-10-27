// CacheStorageService.qml - owns cache files, avatar processes and the serialization worker.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../JS/Helpers/CacheCommands.js" as CacheCommands
import ".."

Item {
    id: storage

    property string avatarsDirectory: ""
    property string cacheDirectory: ""
    property string cacheFilePath: ""
    property string objectsDirectory: ""
    property bool workerEnabled: true
    readonly property var workerObject: cacheWorkerLoader.item

    signal avatarDownloadFinished(string login, string localUrl, int generation, bool success)
    signal avatarValidationFinished(string output)
    signal backupFinished(int exitCode, string message, string backupPath)
    signal cacheFileMissing
    signal cacheFileRead(string text)
    signal cacheFileReadFailed(string details)
    signal clearFinished(int exitCode, bool duringInitialize)
    signal directoryReady(bool success)
    signal directoryResolved(string path)
    signal saveFailed
    signal workerMessage(var message)

    // Preserve the unreadable file before its owner allows any replacement write.
    function backupDamagedCache(message, backupPath) {
        damagedCacheBackupComponent.createObject(storage, {
            failureMessage: message,
            backupPath: backupPath,
            command: ["cp", "-p", "--", cacheFilePath, backupPath],
            running: true
        });
    }
    // Empty the cache root and recreate its subdirectories.
    function clearCache(duringInitialize) {
        clearCacheComponent.createObject(storage, {
            duringInitialize: duringInitialize,
            command: CacheCommands.buildCacheResetCommand(cacheDirectory, objectsDirectory, avatarsDirectory),
            running: true
        });
    }
    // Create both cache subdirectories before reading or resetting the cache.
    function createDirectories() {
        initDirComponent.createObject(storage, {
            command: ["mkdir", "-p", objectsDirectory, avatarsDirectory],
            running: true
        });
    }
    // Download public avatars without credentials, using the provider's retry policy.
    function downloadAvatar(login, remoteUrl, generation, retryPolicy) {
        let localPath = avatarsDirectory + "/" + login + ".png";
        // Dux dl is suitable for public avatars; authenticated API calls need curl's stdin headers.
        avatarDownloadComponent.createObject(storage, {
            login: login,
            localPath: localPath,
            generation: generation,
            downloadCommand: ["dms", "dl", "--connect-timeout", GitHubConstants.avatarDownloadConnectTimeoutSeconds, "--timeout", GitHubConstants.avatarDownloadMaxTimeSeconds, "-o", localPath, "--", remoteUrl],
            maximumRetries: retryPolicy.retryCount,
            retryWindowMs: retryPolicy.maximumRetryTimeSeconds * 1000,
            retryDelayMs: GitHubConstants.avatarDownloadRetryDelayMs
        });
    }
    // Read the cache with a process because FileView.reload is unreliable during startup.
    function readCacheFile() {
        readCacheComponent.createObject(storage, {
            command: ["env", "LC_ALL=C", "cat", cacheFileView.path || cacheFilePath],
            running: true
        });
    }
    // Remove a failed download only when its path lies under the avatar directory.
    function removeAvatarFile(localPath) {
        if (!localPath || localPath.indexOf(avatarsDirectory + "/") !== 0)
            return;
        removeAvatarComponent.createObject(storage, {
            command: ["rm", "-f", localPath],
            running: true
        });
    }

    // Resolve the cache root using XDG_CACHE_HOME or HOME/.cache.
    function resolveDirectory() {
        resolveDirComponent.createObject(storage, {
            command: CacheCommands.buildCacheRootResolveCommand(GitHubConstants.cacheRootDirectoryName),
            running: true
        });
    }
    // Validate avatar files without interpolating paths into shell source.
    function validateAvatarFiles(logins) {
        let paths = [];
        for (let index = 0; index < logins.length; index++)
            paths.push(avatarsDirectory + "/" + logins[index] + ".png");
        avatarValidateComponent.createObject(storage, {
            command: CacheCommands.buildAvatarValidationCommand(paths),
            running: true
        });
    }
    // Write worker-serialized metadata atomically through FileView.
    function writeCacheText(text) {
        cacheFileView.setText(text);
    }

    visible: false

    FileView {
        id: cacheFileView

        atomicWrites: true
        blockLoading: false
        path: storage.cacheFilePath
        preload: false
    }
    Connections {
        // Record a failure if FileView is ever reloaded outside the startup process.
        function onLoadFailed(error) {
            PluginLogger.error("cache", "Cache file could not be loaded");
        }
        // Surface failed atomic writes to the cache owner.
        function onSaveFailed(error) {
            PluginLogger.error("cache", "Cache file could not be saved");
            storage.saveFailed();
        }

        target: cacheFileView
    }
    Loader {
        id: cacheWorkerLoader

        active: storage.workerEnabled

        sourceComponent: Component {
            WorkerScript {
                source: Qt.resolvedUrl("../../JS/BackgroundWorkers/CacheBackgroundWorker.js")

                onMessage: message => storage.workerMessage(message)
            }
        }
    }
    Component {
        id: initDirComponent

        Process {
            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: exitCode => {
                storage.directoryReady(exitCode === 0);
                destroy();
            }
        }
    }
    Component {
        id: resolveDirComponent

        Process {
            id: resolveDirProcess

            property string captured: ""

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: line => resolveDirProcess.captured = line.trim()
            }

            onExited: exitCode => {
                storage.directoryResolved(exitCode === 0 ? captured : "");
                destroy();
            }
        }
    }
    Component {
        id: readCacheComponent

        Process {
            id: readCacheProcess

            property var errorLines: []
            property var lines: []

            stderr: SplitParser {
                onRead: line => readCacheProcess.errorLines.push(line)
            }
            stdout: SplitParser {
                onRead: line => readCacheProcess.lines.push(line)
            }

            onExited: exitCode => {
                if (exitCode === 0)
                    storage.cacheFileRead(lines.join("\n"));
                else if (errorLines.join("\n").toLowerCase().indexOf("no such file or directory") >= 0)
                    storage.cacheFileMissing();
                else
                    storage.cacheFileReadFailed(errorLines.join(" "));
                destroy();
            }
        }
    }
    Component {
        id: clearCacheComponent

        Process {
            property bool duringInitialize: false

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: exitCode => {
                storage.clearFinished(exitCode, duringInitialize);
                destroy();
            }
        }
    }
    Component {
        id: damagedCacheBackupComponent

        Process {
            property string backupPath: ""
            property string failureMessage: ""

            onExited: exitCode => {
                storage.backupFinished(exitCode, failureMessage, backupPath);
                destroy();
            }
        }
    }
    Component {
        id: avatarValidateComponent

        Process {
            id: avatarValidationProcess

            property string output: ""

            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: line => avatarValidationProcess.output = (avatarValidationProcess.output ? avatarValidationProcess.output + "\n" : "") + line
            }

            onExited: exitCode => {
                storage.avatarValidationFinished(output);
                destroy();
            }
        }
    }
    Component {
        id: avatarDownloadComponent

        AvatarDownloadWorker {
            property int generation: 0
            property string localPath: ""
            property string login: ""

            onFinished: success => {
                if (!success)
                    storage.removeAvatarFile(localPath);
                storage.avatarDownloadFinished(login, success ? ("file://" + localPath) : "", generation, success);
                destroy();
            }
        }
    }
    Component {
        id: removeAvatarComponent

        Process {
            stderr: SplitParser {
                onRead: function (line) {}
            }
            stdout: SplitParser {
                onRead: function (line) {}
            }

            onExited: exitCode => destroy()
        }
    }
}
