// GitHubConstants.js - Hardcoded values shared by JavaScript files in the GitHub Inbox plugin.
//
// This file mirrors the subset of QML/Constants.qml that is needed by JS code
// running outside the main QML context (e.g., WorkerScript).
//
// WorkerScript usage:  importScripts("GitHubConstants.js")
//                      then access GHC.SOME_CONSTANT
//
// GitHubHelpers.js references these values as local constants defined at the
// top of that file (pragma-library JS modules cannot use importScripts).

var GHC = (function() {
    "use strict";

    return {
        // -- Plugin Identity --------------------------------------------------

        /// The DMS plugin namespace ID. Must match Constants.qml and plugin.json.
        pluginNamespaceId: "github-inbox",

        // -- GitHub URLs & Headers -------------------------------------------

        /// Root URL of the GitHub REST API v3.
        githubApiBaseUrl: "https://api.github.com",

        /// Root URL of the GitHub web interface.
        githubWebBaseUrl: "https://github.com",

        /// Canonical GitHub inbox page URL.
        githubInboxFallbackUrl: "https://github.com/notifications",

        // -- Payload Splitting Tokens ----------------------------------------

        /// Sentinel injected between successive inbox message page responses.
        fetchPayloadSplitToken: "__GH_PARTICIPATING_SPLIT__",

        /// Sentinel injected between successive author-detail API responses.
        authorPayloadSplitToken: "__GH_AUTHOR_SPLIT__",

        // -- API Request Sizing ----------------------------------------------

        /// Number of inbox message items sent in each worker-script chunk message.
        messagesParseChunkSize: 80,

        /// Pixel size appended to GitHub avatar URLs to control the fetched
        /// image resolution (e.g. ".png?size=128").
        avatarDefaultSizePx: 128,

        // -- Poll Settings - Defaults & Bounds -------------------------------

        /// Default poll interval in seconds when no setting is persisted.
        defaultPollIntervalSeconds: 120,

        /// Minimum acceptable poll interval in seconds.
        minPollIntervalSeconds: 60,

        // -- Display Limits --------------------------------------------------

        /// Maximum unread count rendered as a number before showing "999+".
        unreadCountDisplayMax: 999,

        // -- Internal State Keys ---------------------------------------------

        /// Object key used for the fall-through expand/collapse default.
        expandedStateDefaultKey: "__defaultExpanded"
    };
}());
