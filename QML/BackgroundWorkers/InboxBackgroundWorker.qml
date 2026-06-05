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
    property real targetOldestVisibleUpdatedAtMs: 0
    property string fetchSplitToken: GitHubConstants.fetchPayloadSplitToken

    // -- State ----------------------------------------------------------------
    property bool isLoading: false
    property bool fetchQueued: false
    property bool lastFetchWasComplete: false
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
        lastFetchWasComplete = false
        var generation = fetchGeneration
        ApiCallStats.resetSession()

        var targetOldest = Math.max(0, Math.floor(targetOldestVisibleUpdatedAtMs || 0))
        var maxPages = targetOldest > 0
            ? GitHubConstants.dynamicFetchMaxPages
            : GitHubConstants.firstRunFetchPageCount
        var command = buildDynamicFetchCommand(targetOldest, maxPages)
        _perfLog("fetch — spawning curl, targetOldestMs=" + targetOldest
                 + " maxPages=" + maxPages)
        var process = fetchComponentDef.createObject(fetcher, {
            generation: generation
        })
        process.command = command
        process.running = true
    }

    function buildDynamicFetchCommand(targetOldestMs, maxPages) {
        var script = ""
            + "token=$1\n"
            + "split=$2\n"
            + "page_size=$3\n"
            + "target_oldest_ms=$4\n"
            + "max_pages=$5\n"
            + "connect_timeout=$6\n"
            + "max_time=$7\n"
            + "accept_header=$8\n"
            + "api_version=$9\n"
            + "inbox_url=${10}\n"
            + "command -v jq >/dev/null 2>&1 || exit 127\n"
            + "base_query=\"per_page=${page_size}\"\n"
            + "all_base_url=\"${inbox_url}?${base_query}&all=true\"\n"
            + "participating_base_url=\"${inbox_url}?${base_query}&all=true&participating=true\"\n"
            + "page=1\n"
            + "pages=0\n"
            + "while [ \"$page\" -le \"$max_pages\" ]; do\n"
            + "  body=$(curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H \"Authorization: token $token\" \"${all_base_url}&page=${page}\") || exit $?\n"
            + "  printf '%s\\n%s\\n' \"$body\" \"$split\"\n"
            + "  pages=$page\n"
            + "  length=$(printf '%s\\n' \"$body\" | jq 'if type == \"array\" then length else -1 end') || exit $?\n"
            + "  if [ \"$length\" -lt 0 ]; then exit 22; fi\n"
            + "  if [ \"$length\" -lt \"$page_size\" ]; then break; fi\n"
            + "  if [ \"$target_oldest_ms\" -gt 0 ]; then\n"
            + "    oldest_sec=$(printf '%s\\n' \"$body\" | jq '[.[].updated_at | fromdateiso8601?] | min // 0') || exit $?\n"
            + "    oldest_ms=$((oldest_sec * 1000))\n"
            + "    if [ \"$oldest_ms\" -gt 0 ] && [ \"$oldest_ms\" -le \"$target_oldest_ms\" ]; then break; fi\n"
            + "  fi\n"
            + "  page=$((page + 1))\n"
            + "done\n"
            + "p_page=1\n"
            + "while [ \"$p_page\" -le \"$pages\" ]; do\n"
            + "  body=$(curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H \"Authorization: token $token\" \"${participating_base_url}&page=${p_page}\") || exit $?\n"
            + "  printf '%s\\n%s\\n' \"$body\" \"$split\"\n"
            + "  p_page=$((p_page + 1))\n"
            + "done\n"
            + "printf '__GH_FETCH_PAGES=%s\\n' \"$pages\" >&2\n"

        return [
            "sh", "-c", script, "github-inbox-fetch",
            token,
            fetchSplitToken,
            String(GitHubConstants.messagesApiPageSize),
            String(targetOldestMs),
            String(maxPages),
            String(GitHubConstants.curlConnectTimeoutSeconds),
            String(GitHubConstants.curlMaxTimeSeconds),
            GitHubConstants.httpAcceptHeader,
            GitHubConstants.githubApiVersionHeader,
            GitHubConstants.githubInboxApiUrl
        ]
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
            property var _stderrLines: []

            stdout: SplitParser {
                onRead: line => _chunks.push(line)
            }

            stderr: SplitParser {
                onRead: line => {
                    var trimmed = line.trim()
                    if (trimmed) {
                        _stderrLines.push(trimmed)
                        if (trimmed.indexOf("__GH_FETCH_PAGES=") !== 0)
                            console.warn("[GitHubInbox] fetch:", line)
                    }
                }
            }

            onExited: exitCode => {
                if (generation !== fetcher.fetchGeneration) {
                    destroy()
                    return
                }

                if (exitCode !== 0) {
                    fetcher.isLoading = false
                    fetcher.fetchError(fetcher._describeFetchFailure(_stderrLines.join("\n")))
                    fetcher.retryIfQueued()
                    destroy()
                    return
                }

                var nextSeq = fetcher.parseRequestSeq + 1
                fetcher.parseRequestSeq = nextSeq
                var pageCount = fetcher._parseFetchedPageCount(_stderrLines)
                if (pageCount > 0)
                    ApiCallStats.recordCalls(pageCount * 2)
                fetcher._perfLog("curl done, sending payload to WorkerScript (len=" + (_chunks.join("\n").length) + ")")
                parseWorker.sendMessage({
                    seq: nextSeq,
                    payloadText: _chunks.join("\n") + "\n",
                    separator: fetcher.fetchSplitToken,
                    allSegmentCount: pageCount,
                    targetOldestVisibleUpdatedAtMs: fetcher.targetOldestVisibleUpdatedAtMs,
                    pageSize: GitHubConstants.messagesApiPageSize,
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
                fetcher.lastFetchWasComplete = !!message.isComplete
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

    function _describeFetchFailure(stderrText) {
        var text = String(stderrText || "")
        var lower = text.toLowerCase()

        if (lower.indexOf("could not resolve host") >= 0)
            return "Connection error: could not resolve api.github.com."
        if (lower.indexOf("failed to connect") >= 0 || lower.indexOf("connection refused") >= 0)
            return "Connection error: failed to connect to GitHub."
        if (lower.indexOf("timed out") >= 0 || lower.indexOf("operation timed out") >= 0)
            return "Connection error: GitHub request timed out."
        if (lower.indexOf("ssl") >= 0 || lower.indexOf("certificate") >= 0)
            return "Connection error: TLS/SSL failure while contacting GitHub."
        if (lower.indexOf("401") >= 0 || lower.indexOf("bad credentials") >= 0)
            return "Authentication error: GitHub token was rejected."
        if (lower.indexOf("403") >= 0 || lower.indexOf("rate limit") >= 0)
            return "GitHub API error: request was forbidden or rate limited."
        if (text)
            return "GitHub request failed: " + text.split("\n")[0]
        return "GitHub request failed. Check token or network."
    }

    function _parseFetchedPageCount(lines) {
        var source = lines || []
        for (var index = source.length - 1; index >= 0; index--) {
            var line = String(source[index] || "").trim()
            var marker = "__GH_FETCH_PAGES="
            if (line.indexOf(marker) !== 0)
                continue
            var value = parseInt(line.substring(marker.length))
            return isNaN(value) ? 0 : value
        }
        return 0
    }
}
