// InboxBackgroundWorker.qml - Fetches GitHub inbox messages via curl, parses in background
//
// Encapsulates the multi-page curl fetch and WorkerScript-based JSON parsing.
// Emits signals for each phase of the result so the parent can update state.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: fetcher

    property int fetchGeneration: 0
    property bool fetchQueued: false
    property string fetchSplitToken: GitHubConstants.fetchPayloadSplitToken

    // -- State ----------------------------------------------------------------
    property bool isLoading: false
    property bool lastFetchWasComplete: false
    property int parseRequestSeq: 0
    property var parserWorker: null
    property bool parserWorkerEnabled: true
    property var providerApi: null
    property real targetOldestVisibleUpdatedAtMs: 0

    // -- Configuration --------------------------------------------------------
    property string token: ""

    // =========================================================================
    //  WORKER SCRIPT (author results are forwarded via authorResultReceived)
    // =========================================================================

    signal authorResultReceived(var message)

    // -- Signals --------------------------------------------------------------
    signal fetchBegin(int totalCount, int unreadCount)
    signal fetchChunk(var items, bool isLast)
    signal fetchComplete(var items, int unreadCount)
    signal fetchError(string errorMessage)

    // Handle this workflow result at the ownership boundary and preserve failure visibility.
    function _describeFetchFailure(stderrText) {
        let text = String(stderrText || "");
        let lower = text.toLowerCase();

        if (lower.indexOf("could not resolve host") >= 0)
            return "Connection error: could not resolve api.github.com.";
        if (lower.indexOf("failed to connect") >= 0 || lower.indexOf("connection refused") >= 0)
            return "Connection error: failed to connect to GitHub.";
        if (lower.indexOf("timed out") >= 0 || lower.indexOf("operation timed out") >= 0)
            return "Connection error: GitHub request timed out.";
        if (lower.indexOf("ssl") >= 0 || lower.indexOf("certificate") >= 0)
            return "Connection error: TLS/SSL failure while contacting GitHub.";
        if (lower.indexOf("401") >= 0 || lower.indexOf("bad credentials") >= 0)
            return "Authentication error: GitHub token was rejected.";
        if (lower.indexOf("403") >= 0 || lower.indexOf("rate limit") >= 0)
            return "GitHub API error: request was forbidden or rate limited.";
        return "GitHub request failed. Check token or network.";
    }
    // Decode only recognized response fields while preserving notification context.
    function _parseFetchMarker(lines, marker) {
        let source = lines || [];
        for (let index = source.length - 1; index >= 0; index--) {
            let line = String(source[index] || "").trim();
            if (line.indexOf(marker) !== 0)
                continue;
            let value = parseInt(line.substring(marker.length));
            return isNaN(value) ? 0 : value;
        }
        return 0;
    }

    // =========================================================================
    //  PUBLIC API
    // =========================================================================

    // -- Perf logging helper --------------------------------------------------
    function _perfLog(label) {
        PluginLogger.debug("InboxBackgroundWorker", label);
    }
    // Build a provider-specific destination from validated subject data.
    function buildDynamicFetchCommand(targetOldestMs, maxPages) {
        let retryPolicy = providerApi.getRetryPolicy();
        let script = "" + "IFS= read -r token || exit 1\n" + "split=$1\n" + "page_size=$2\n" + "target_oldest_ms=$3\n" + "max_pages=$4\n" + "connect_timeout=$5\n" + "max_time=$6\n" + "accept_header=$7\n" + "api_version=$8\n" + "inbox_url=$9\n" + "http2_retries=${10}\n" + "http2_retry_delay_base_seconds=${11}\n" + "curl_retry_count=${12}\n" + "curl_retry_max_time=${13}\n" + "command -v jq >/dev/null 2>&1 || exit 127\n" + "retry_count=0\n" + "fetch_page() {\n" + "  page_url=$1\n" + "  attempts=0\n" + "  while :; do\n" + "    body=$(printf 'Authorization: token %s\\n' \"$token\" | curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" --retry \"$curl_retry_count\" --retry-connrefused --retry-max-time \"$curl_retry_max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H @- \"$page_url\")\n" + "    status=$?\n" + "    if [ \"$status\" -eq 0 ]; then return 0; fi\n" + "    if [ \"$status\" -ne 92 ] || [ \"$attempts\" -ge \"$http2_retries\" ]; then return \"$status\"; fi\n" + "    retry_delay_seconds=$((http2_retry_delay_base_seconds << attempts))\n" + "    sleep \"$retry_delay_seconds\" || return $?\n" + "    attempts=$((attempts + 1))\n" + "    retry_count=$((retry_count + 1))\n" + "  done\n" + "}\n" + "base_query=\"per_page=${page_size}\"\n" + "all_base_url=\"${inbox_url}?${base_query}&all=true\"\n" + "participating_base_url=\"${inbox_url}?${base_query}&all=true&participating=true\"\n" + "page=1\n" + "pages=0\n" + "while [ \"$page\" -le \"$max_pages\" ]; do\n" + "  fetch_page \"${all_base_url}&page=${page}\" || exit $?\n" + "  printf '%s\\n%s\\n' \"$body\" \"$split\"\n" + "  pages=$page\n" + "  length=$(printf '%s\\n' \"$body\" | jq 'if type == \"array\" then length else -1 end') || exit $?\n" + "  if [ \"$length\" -lt 0 ]; then exit 22; fi\n" + "  if [ \"$length\" -lt \"$page_size\" ]; then break; fi\n" + "  if [ \"$target_oldest_ms\" -gt 0 ]; then\n" + "    oldest_sec=$(printf '%s\\n' \"$body\" | jq '[.[].updated_at | fromdateiso8601?] | min // 0') || exit $?\n" + "    oldest_ms=$((oldest_sec * 1000))\n" + "    if [ \"$oldest_ms\" -gt 0 ] && [ \"$oldest_ms\" -le \"$target_oldest_ms\" ]; then break; fi\n" + "  fi\n" + "  page=$((page + 1))\n" + "done\n" + "p_page=1\n" + "while [ \"$p_page\" -le \"$pages\" ]; do\n" + "  fetch_page \"${participating_base_url}&page=${p_page}\" || exit $?\n" + "  printf '%s\\n%s\\n' \"$body\" \"$split\"\n" + "  p_page=$((p_page + 1))\n" + "done\n" + "printf '__GH_FETCH_PAGES=%s\\n__GH_FETCH_RETRIES=%s\\n' \"$pages\" \"$retry_count\" >&2\n";

        return ["bash", "-c", script, "github-inbox-fetch", fetchSplitToken, String(GitHubConstants.messagesApiPageSize), String(targetOldestMs), String(maxPages), String(GitHubConstants.curlConnectTimeoutSeconds), String(GitHubConstants.curlMaxTimeSeconds), GitHubConstants.httpAcceptHeader, GitHubConstants.githubApiVersionHeader, providerApi.buildInboxUrl(), String(retryPolicy.http2RetryCount), String(retryPolicy.http2RetryDelayBaseSeconds), String(retryPolicy.retryCount), String(retryPolicy.maximumRetryTimeSeconds)];
    }
    // Invalidate pending generations so obsolete responses cannot enter current state.
    function cancel() {
        fetchGeneration = fetchGeneration + 1;
        parseRequestSeq = parseRequestSeq + 1;
        isLoading = false;
        fetchQueued = false;
    }
    // Start a bounded request cycle using the currently configured provider facade.
    function fetch() {
        _perfLog("fetch --- called");
        if (!token)
            return;
        if (!providerApi) {
            fetchError("The GitHub provider is unavailable.");
            return;
        }

        if (isLoading) {
            fetchQueued = true;
            return;
        }

        isLoading = true;
        lastFetchWasComplete = false;
        let generation = fetchGeneration;
        ApiCallStats.resetSession();

        let targetOldest = Math.max(0, Math.floor(targetOldestVisibleUpdatedAtMs || 0));
        let maxPages = targetOldest > 0 ? GitHubConstants.dynamicFetchMaxPages : GitHubConstants.firstRunFetchPageCount;
        let command = buildDynamicFetchCommand(targetOldest, maxPages);
        _perfLog("fetch --- spawning curl, targetOldestMs=" + targetOldest + " maxPages=" + maxPages);
        fetchComponentDef.createObject(fetcher, {
            generation: generation,
            requestToken: token,
            command: command,
            running: true
        });
    }
    // Consume one deferred request after the current generation has finished.
    function retryIfQueued() {
        if (fetchQueued) {
            fetchQueued = false;
            Qt.callLater(fetch);
        }
    }

    // Expose sendMessage for AuthorBackgroundWorker to offload parsing
    function sendWorkerMessage(message) {
        if (parserWorker)
            parserWorker.sendMessage(message);
    }

    visible: false

    // =========================================================================
    //  PROCESS COMPONENT
    // =========================================================================

    Component {
        id: fetchComponentDef

        Process {
            id: fetchProcess

            property var _chunks: []
            property var _stderrLines: []
            property int generation: 0
            property string requestToken: ""

            stdinEnabled: true

            stderr: SplitParser {
                onRead: line => {
                    let trimmed = line.trim();
                    if (trimmed)
                        fetchProcess._stderrLines.push(trimmed);
                }
            }
            stdout: SplitParser {
                onRead: line => fetchProcess._chunks.push(line)
            }

            onExited: exitCode => {
                if (generation !== fetcher.fetchGeneration) {
                    destroy();
                    return;
                }

                if (exitCode !== 0) {
                    PluginLogger.error("fetch", "GitHub inbox request failed with exit code " + exitCode);
                    fetcher.isLoading = false;
                    fetcher.fetchError(fetcher._describeFetchFailure(fetchProcess._stderrLines.join("\n")));
                    fetcher.retryIfQueued();
                    destroy();
                    return;
                }

                let nextSeq = fetcher.parseRequestSeq + 1;
                fetcher.parseRequestSeq = nextSeq;
                let pageCount = fetcher._parseFetchMarker(fetchProcess._stderrLines, "__GH_FETCH_PAGES=");
                let retryCount = fetcher._parseFetchMarker(fetchProcess._stderrLines, "__GH_FETCH_RETRIES=");
                if (pageCount > 0)
                    ApiCallStats.recordCalls(pageCount * 2 + retryCount);
                fetcher._perfLog("curl done, sending payload to WorkerScript (len=" + (fetchProcess._chunks.join("\n").length) + ")");
                if (!fetcher.parserWorker) {
                    fetcher.isLoading = false;
                    fetcher.fetchError("The inbox parser is unavailable.");
                    fetcher.retryIfQueued();
                    destroy();
                    return;
                }
                fetcher.parserWorker.sendMessage({
                    seq: nextSeq,
                    payloadText: fetchProcess._chunks.join("\n") + "\n",
                    separator: fetcher.fetchSplitToken,
                    allSegmentCount: pageCount,
                    targetOldestVisibleUpdatedAtMs: fetcher.targetOldestVisibleUpdatedAtMs,
                    pageSize: GitHubConstants.messagesApiPageSize,
                    chunkSize: GitHubConstants.messagesParseChunkSize
                });

                destroy();
            }
            onStarted: {
                write(requestToken + "\n");
                stdinEnabled = false;
                requestToken = "";
            }
        }
    }
    Loader {
        id: parserWorkerLoader

        active: fetcher.parserWorkerEnabled

        sourceComponent: Component {
            WorkerScript {
                source: Qt.resolvedUrl("../../JS/Integrations/GitHub/InboxParserBackgroundWorker.js")

                onMessage: function (message) {
                    fetcher._perfLog("WorkerScript message: action=" + (message.action || "inbox") + " phase=" + (message.phase || "n/a"));
                    // Author parse results are forwarded to the parent (AuthorBackgroundWorker
                    // will connect to the authorResultReceived signal).
                    if (message.action === "authorsResult") {
                        fetcher.authorResultReceived(message);
                        return;
                    }

                    if (message.seq !== fetcher.parseRequestSeq)
                        return;
                    if (message.error) {
                        if (message.failure)
                            PluginLogger.error("inbox parser", message.failure.details);
                        fetcher.isLoading = false;
                        fetcher.fetchError(message.error);
                        fetcher.retryIfQueued();
                        return;
                    }

                    if (message.phase === "begin") {
                        let totalCount = parseInt(message.totalCount || 0);
                        let unreadCount = parseInt(message.unreadCount || 0);
                        fetcher.lastFetchWasComplete = !!message.isComplete;
                        fetcher.fetchBegin(totalCount, unreadCount);

                        if (totalCount === 0) {
                            fetcher.isLoading = false;
                            fetcher.retryIfQueued();
                        }
                        return;
                    }

                    if (message.phase === "chunk") {
                        let chunk = message.items || [];
                        fetcher.fetchChunk(chunk, !!message.isLast);

                        if (message.isLast) {
                            fetcher.isLoading = false;
                            fetcher.retryIfQueued();
                        }
                        return;
                    }

                    // Legacy single-message path
                    fetcher.fetchComplete(message.items || [], parseInt(message.unreadCount || 0));
                    fetcher.isLoading = false;
                    fetcher.retryIfQueued();
                }
            }
        }

        onItemChanged: fetcher.parserWorker = item
    }
}
