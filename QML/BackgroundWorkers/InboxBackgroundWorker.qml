// InboxBackgroundWorker.qml - Fetches GitHub inbox messages via curl, parses in background
//
// Encapsulates the multi-page curl fetch and WorkerScript-based JSON parsing.
// Emits signals for each phase of the result so the parent can update state.

import QtQuick
import Quickshell.Io
import ".."
import "../../JS/GitHubHelpers.js" as GitHub

Item {
    id: fetcher
    visible: false

    // -- Configuration --------------------------------------------------------
    property string token: ""
    property int fetchPageCount: 1
    property string fetchSplitToken: GitHubConstants.fetchPayloadSplitToken
    property var doneThreadState: ({})

    // -- State ----------------------------------------------------------------
    property bool isLoading: false
    property bool fetchQueued: false
    property int parseRequestSeq: 0
    property int fetchGeneration: 0

    // -- Signals --------------------------------------------------------------
    signal fetchBegin(int totalCount, int unreadCount)
    signal fetchChunk(var items, bool isLast)
    signal fetchComplete(var items, int unreadCount)
    signal fetchError(string errorMessage)

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        if (!GitHubConstants.debugPerformanceLogging) return
        console.warn("[GitHubInbox PERF] InboxBackgroundWorker: " + label)
    }

    function fetch() {
        _perfLog("fetch — called")
        if (!token)
            return

        if (isLoading) {
            fetchQueued = true
            return
        }

        isLoading = true
        var generation = fetchGeneration
        ApiCallStats.resetSession()

        var pages = Math.max(1, fetchPageCount)
        var baseQuery = "per_page=" + GitHubConstants.messagesApiPageSize
        var allBaseUrl = GitHubConstants.githubInboxApiUrl + "?" + baseQuery + "&all=true"
        var participatingBaseUrl = GitHubConstants.githubInboxApiUrl + "?" + baseQuery + "&participating=true"
        var command = ["curl"]

        // Fetch "all" pages first
        for (var page = 1; page <= pages; page++) {
            if (command.length > 1)
                command.push("--next")
            command.push(
                "-sS",
                "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds,
                "--max-time", GitHubConstants.curlMaxTimeSeconds,
                "-H", "Accept: " + GitHubConstants.httpAcceptHeader,
                "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader,
                "-H", "Authorization: token " + token,
                "-w", "\n" + fetchSplitToken + "\n",
                allBaseUrl + "&page=" + page
            )
        }

        // Fetch "participating" pages to resolve the participation flag
        for (var pPage = 1; pPage <= pages; pPage++) {
            command.push("--next")
            command.push(
                "-sS",
                "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds,
                "--max-time", GitHubConstants.curlMaxTimeSeconds,
                "-H", "Accept: " + GitHubConstants.httpAcceptHeader,
                "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader,
                "-H", "Authorization: token " + token,
                "-w", "\n" + fetchSplitToken + "\n",
                participatingBaseUrl + "&page=" + pPage
            )
        }

        ApiCallStats.recordCalls(pages * 2)
        _perfLog("fetch — spawning curl, pages=" + pages)
        var process = fetchComponentDef.createObject(fetcher, {
            generation: generation
        })
        process.command = command
        process.running = true
    }

    function cancel() {
        fetchGeneration = fetchGeneration + 1
        parseRequestSeq = parseRequestSeq + 1
        isLoading = false
        fetchQueued = false
    }

    function retryIfQueued() {
        if (fetchQueued) {
            fetchQueued = false
            Qt.callLater(fetch)
        }
    }

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: fetchComponentDef

        Process {
            property int generation: 0
            property var _chunks: []

            stdout: SplitParser {
                onRead: line => _chunks.push(line)
            }

            stderr: SplitParser {
                onRead: line => {
                    if (line.trim())
                        console.warn("[GitHubInbox] fetch:", line)
                }
            }

            onExited: exitCode => {
                if (generation !== fetcher.fetchGeneration) {
                    destroy()
                    return
                }

                if (exitCode !== 0) {
                    fetcher.isLoading = false
                    fetcher.fetchError("Request failed. Check token or network.")
                    fetcher.retryIfQueued()
                    destroy()
                    return
                }

                var nextSeq = fetcher.parseRequestSeq + 1
                fetcher.parseRequestSeq = nextSeq
                fetcher._perfLog("curl done, sending payload to WorkerScript (len=" + (_chunks.join("\n").length) + ")")
                parseWorker.sendMessage({
                    seq: nextSeq,
                    payloadText: _chunks.join("\n") + "\n",
                    separator: fetcher.fetchSplitToken,
                    allSegmentCount: fetcher.fetchPageCount,
                    doneThreadState: fetcher.doneThreadState,
                    chunkSize: GitHubConstants.messagesParseChunkSize
                })

                destroy()
            }
        }
    }

    // =========================================================================
    //  WORKER SCRIPT (author results are forwarded via authorResultReceived)
    // =========================================================================

    signal authorResultReceived(var message)

    WorkerScript {
        id: parseWorker
        source: Qt.resolvedUrl("../../JS/BackgroundWorkers/InboxParserBackgroundWorker.js")

        onMessage: function(message) {
            fetcher._perfLog("WorkerScript message: action=" + (message.action || "inbox") + " phase=" + (message.phase || "n/a"))
            // Author parse results are forwarded to the parent (AuthorBackgroundWorker
            // will connect to the authorResultReceived signal).
            if (message.action === "authorsResult") {
                fetcher.authorResultReceived(message)
                return
            }

            if (message.seq !== fetcher.parseRequestSeq)
                return

            if (message.error) {
                fetcher.isLoading = false
                fetcher.fetchError(message.error)
                fetcher.retryIfQueued()
                return
            }

            if (message.phase === "begin") {
                var totalCount = parseInt(message.totalCount || 0)
                var unreadCount = parseInt(message.unreadCount || 0)
                fetcher.fetchBegin(totalCount, unreadCount)

                if (totalCount === 0) {
                    fetcher.isLoading = false
                    fetcher.retryIfQueued()
                }
                return
            }

            if (message.phase === "chunk") {
                var chunk = message.items || []
                fetcher.fetchChunk(chunk, !!message.isLast)

                if (message.isLast) {
                    fetcher.isLoading = false
                    fetcher.retryIfQueued()
                }
                return
            }

            // Legacy single-message path
            fetcher.fetchComplete(message.items || [], parseInt(message.unreadCount || 0))
            fetcher.isLoading = false
            fetcher.retryIfQueued()
        }
    }

    // Expose sendMessage for AuthorBackgroundWorker to offload parsing
    function sendWorkerMessage(msg) {
        parseWorker.sendMessage(msg)
    }
}
