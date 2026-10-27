// InboxMutationService.qml - runs one authenticated inbox mutation and reports its result.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service

    property bool isLoading: false
    property bool isOperating: false
    property int operationGeneration: 0
    property var providerApi: null
    property string token: ""

    signal mutationFinished(string actionType, string threadId, string repositoryFullName, bool success, string errorMessage)
    signal operationError(string errorMessage)

    // Dux dl is GET-only and cannot accept secret headers through stdin; curl supports both requirements.
    function buildMutationCommand(method, url, payloadJson) {
        let command = ["bash", "-c", "exec \"$@\" -H @-", "github-inbox-mutation", "curl", "-sS", "-o", "/dev/null", "-w", GitHubConstants.curlStatusCodeFormat, "--connect-timeout", GitHubConstants.curlConnectTimeoutSeconds, "--max-time", GitHubConstants.curlMaxTimeSeconds, "-X", method, "-H", "Accept: " + GitHubConstants.httpAcceptHeader, "-H", "X-GitHub-Api-Version: " + GitHubConstants.githubApiVersionHeader];
        command = command.concat(providerApi.buildCurlRetryArguments());
        if (payloadJson)
            command.push("-H", "Content-Type: application/json", "-d", payloadJson);
        command.push(url);
        return command;
    }
    // Ignore results from processes that belonged to the previous widget state.
    function reset() {
        operationGeneration = operationGeneration + 1;
        isOperating = false;
    }
    // Start a validated provider request while keeping the token out of process arguments.
    function run(request, actionType, threadId, repositoryFullName) {
        if (!request) {
            operationError("The GitHub provider rejected this inbox operation.");
            PluginLogger.error("provider", "Rejected an invalid inbox mutation request");
            return;
        }
        if (!token || isOperating || isLoading)
            return;
        isOperating = true;
        let process = operationComponentDef.createObject(service, {
            requestToken: token,
            actionType: actionType || "thread_read",
            threadId: threadId || "",
            repositoryFullName: repositoryFullName || "",
            generation: operationGeneration
        });
        ApiCallStats.recordCalls(1);
        process.command = buildMutationCommand(request.method, request.url, request.payloadJson);
        process.running = true;
    }

    visible: false

    Component {
        id: operationComponentDef

        Process {
            id: mutationProcess

            property string _buffer: ""
            property string actionType: "thread_read"
            property int generation: 0
            property string repositoryFullName: ""
            property string requestToken: ""
            property string threadId: ""

            stdinEnabled: true

            stdout: SplitParser {
                onRead: line => mutationProcess._buffer += line
            }

            onExited: exitCode => {
                if (generation !== service.operationGeneration) {
                    destroy();
                    return;
                }
                service.isOperating = false;
                if (exitCode !== 0) {
                    PluginLogger.error("operate", "GitHub inbox operation failed with exit code " + exitCode);
                    service.mutationFinished(actionType, threadId, repositoryFullName, false, "Action failed. Check token permissions.");
                    destroy();
                    return;
                }
                let statusCode = parseInt((_buffer || "").trim());
                let success = !isNaN(statusCode) && statusCode >= GitHubConstants.httpSuccessMin && statusCode < GitHubConstants.httpSuccessMax;
                service.mutationFinished(actionType, threadId, repositoryFullName, success, success ? "" : "Action failed (HTTP " + (isNaN(statusCode) ? "?" : statusCode) + ").");
                destroy();
            }
            onStarted: {
                write("Authorization: token " + requestToken + "\n");
                stdinEnabled = false;
                requestToken = "";
            }
        }
    }
}
