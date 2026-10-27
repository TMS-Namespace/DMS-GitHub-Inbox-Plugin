// AuthorRequestService.qml - runs authenticated author-detail fetches with tokens on stdin.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service

    property string authorSplitToken: GitHubConstants.authorPayloadSplitToken
    property var providerApi: null

    signal finished(var request, int generation, int exitCode, string buffer, int bufferBytes, real startedAt)

    // Build authenticated fetches that use jq to extract actors, workflow details and release links.
    function buildAutomaticAuthorExtractCommand(urls) {
        let retryPolicy = service.providerApi.getRetryPolicy();
        let script = "" + "IFS= read -r token || exit 1\n" + "split=$1\n" + "connect_timeout=$2\n" + "max_time=$3\n" + "accept_header=$4\n" + "api_version=$5\n" + "retry_count=$6\n" + "retry_max_time=$7\n" + "shift 7\n" + "command -v jq >/dev/null 2>&1 || exit 127\n" + "filter='def appslug($profileUrl): if (($profileUrl // \"\") | startswith(\"https://github.com/apps/\")) then (($profileUrl | split(\"?\")[0] | split(\"#\")[0] | split(\"/\"))[-1]) else \"\" end; def rootobj: if type == \"object\" then . else {} end; def nodes: if type == \"array\" then reverse[] else . end; def authorobj: . as $authorObject | (($authorObject.html_url? // $authorObject.htmlUrl? // \"\") as $html | ($authorObject.login? // $authorObject.slug? // appslug($html) // \"\") as $login | ($authorObject.avatar_url? // $authorObject.avatarUrl? // $authorObject.logo_url? // $authorObject.logoUrl? // (if appslug($html) != \"\" then ($html + \".png?size=128\") else \"\" end)) as $avatar | {login:$login, avatarUrl:$avatar, htmlUrl:($html // (if (($authorObject.slug? // \"\") != \"\") then (\"https://github.com/apps/\" + $authorObject.slug) else \"\" end)), type:($authorObject.type? // (if appslug($html) != \"\" then \"App\" else \"\" end))}); def validauthor: authorobj | select((.login // \"\") != \"\" and (((.avatarUrl // \"\") != \"\") or ((.htmlUrl // \"\") != \"\"))); def author_sources($authorObject): $authorObject.actor?, $authorObject.triggering_actor?, $authorObject.user?, $authorObject.author?, $authorObject.sender?, $authorObject.creator?, $authorObject.merged_by?, $authorObject.closed_by?, $authorObject.dismissed_by?; rootobj as $root | {authors:([nodes as $node | author_sources($node) | validauthor] | reduce .[] as $author ([]; if any(.[]; .login == $author.login and .htmlUrl == $author.htmlUrl and .avatarUrl == $author.avatarUrl) then . else . + [$author] end)), subjectWebUrl:($root.html_url // \"\"), subjectReference:(($root.subjectReference // $root.subject_reference // $root.run_number // \"\") | tostring), actionRuns:(($root.workflow_runs // []) | map({htmlUrl:(.html_url // \"\"), runNumber:((.run_number // \"\") | tostring), name:(.name // \"\"), displayTitle:(.display_title // \"\"), headBranch:(.head_branch // \"\"), conclusion:(.conclusion // \"\"), updatedAt:(.updated_at // \"\"), actor:(if .actor? then (.actor | authorobj) else null end), triggeringActor:(if .triggering_actor? then (.triggering_actor | authorobj) else null end)})), release:(if (($root.tag_name // \"\") != \"\" and ($root.html_url // \"\") != \"\") then {tagName:($root.tag_name // \"\"), htmlUrl:($root.html_url // \"\")} else null end)}'\n" + "for url in \"$@\"; do\n" + "  body=$(printf 'Authorization: token %s\\n' \"$token\" | curl -f -sS -L --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" --retry \"$retry_count\" --retry-connrefused --retry-max-time \"$retry_max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H @- \"$url\") || exit $?\n" + "  printf '%s\\n' \"$body\" | jq -c \"$filter\" || exit $?\n" + "  printf '\\n%s\\n' \"$split\"\n" + "done\n";

        let command = ["nice", "-n", "10", "bash", "-c", script, "github-author-extract", authorSplitToken, GitHubConstants.curlConnectTimeoutSeconds, GitHubConstants.curlMaxTimeSeconds, GitHubConstants.httpAcceptHeader, GitHubConstants.githubApiVersionHeader, String(retryPolicy.retryCount), String(retryPolicy.maximumRetryTimeSeconds)];

        for (let urlIndex = 0; urlIndex < urls.length; urlIndex++) {
            if (urls[urlIndex])
                command.push(urls[urlIndex]);
        }
        return command;
    }

    // Build authenticated fetches that return raw response bodies separated by the worker marker.
    function buildRawAuthorFetchCommand(urls) {
        let retryPolicy = service.providerApi.getRetryPolicy();
        let script = "" + "IFS= read -r token || exit 1\n" + "split=$1; connect_timeout=$2; max_time=$3; accept_header=$4; api_version=$5; retry_count=$6; retry_max_time=$7\n" + "shift 7\n" + "for url in \"$@\"; do\n" + "  printf 'Authorization: token %s\\n' \"$token\" | curl -sS --connect-timeout \"$connect_timeout\" --max-time \"$max_time\" --retry \"$retry_count\" --retry-connrefused --retry-max-time \"$retry_max_time\" -H \"Accept: $accept_header\" -H \"X-GitHub-Api-Version: $api_version\" -H @- -w \"\\n$split\\n\" \"$url\"\n" + "done\n";
        let command = ["bash", "-c", script, "github-author-fetch", authorSplitToken, GitHubConstants.curlConnectTimeoutSeconds, GitHubConstants.curlMaxTimeSeconds, GitHubConstants.httpAcceptHeader, GitHubConstants.githubApiVersionHeader, String(retryPolicy.retryCount), String(retryPolicy.maximumRetryTimeSeconds)];
        for (let urlIndex = 0; urlIndex < urls.length; urlIndex++)
            if (urls[urlIndex])
                command.push(urls[urlIndex]);
        return command;
    }

    // Start one already-validated request; its owner tracks concurrency and generation.
    function startRequest(request, generation, token) {
        let command = request.automaticPrefetch ? buildAutomaticAuthorExtractCommand(request.urls) : buildRawAuthorFetchCommand(request.urls);
        authorFetchComponentDef.createObject(service, {
            request: request,
            generation: generation,
            requestToken: token,
            command: command,
            running: true
        });
    }

    visible: false

    Component {
        id: authorFetchComponentDef

        Process {
            id: authorFetchProcess

            property string buffer: ""
            property int bufferBytes: 0
            property int generation: 0
            property var request: null
            property string requestToken: ""
            property real startedAt: Date.now()

            stdinEnabled: true

            stdout: SplitParser {
                onRead: line => {
                    authorFetchProcess.buffer += line + "\n";
                    authorFetchProcess.bufferBytes += line.length + 1;
                }
            }

            onExited: exitCode => {
                service.finished(request, generation, exitCode, buffer, bufferBytes, startedAt);
                destroy();
            }
            onStarted: {
                write(requestToken + "\n");
                stdinEnabled = false;
                requestToken = "";
            }
        }
    }
}
