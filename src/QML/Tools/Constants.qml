// Constants.qml - exported as GitHubConstants in qmldir.
// Central registry of every hardcoded value used by the GitHub Inbox plugin.
//
// All files in this module reference values through this singleton so that a change
// to any magic number, URL, or token only needs to be made in one place.
//
// QML usage:   GitHubConstants.SOME_CONSTANT   (no import needed - registered in qmldir)
// WorkerScript modules keep only the constants they need outside the QML context.

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import "../Services"

QtObject {
    /// Keep native action buttons visible against translucent notification cards.
    readonly property real actionButtonBackgroundOpacity: 0.9

    /// Enables lightweight API/refresh metric collection shown in settings.
    readonly property bool apiCallStatsEnabled: true

    /// Size of the "person" fallback icon shown when no avatar URL is available.
    readonly property int authorAvatarFallbackIconSizePx: 12

    /// Query string appended to author-detail sub-requests to fetch up to 100
    /// items per page and avoid unnecessary pagination.
    readonly property string authorFetchPerPageQuery: "per_page=100"

    /// Maximum changed author threads applied to the UI/cache in one batch.
    readonly property int authorMergeFlushBatchSize: 12

    /// Delay used to batch parsed author updates before notifying the UI model.
    /// This prevents one re-render per fetched thread during background refresh.
    readonly property int authorMergeFlushIntervalMs: 2000

    /// Offset from Theme.fontSizeSmall for the author login / display-name label beside the
    /// avatar.
    readonly property int authorNameFontSizeDelta: -2

    /// Minimum pixel width of the author name label to avoid collapsed text.
    readonly property int authorNameMinWidthPx: 28

    /// Sentinel string injected by curl between successive author-detail API
    /// responses gathered in a single curl invocation.
    readonly property string authorPayloadSplitToken: "__GH_AUTHOR_SPLIT__"

    /// Delay between author-prefetch batches.
    readonly property int authorPrefetchBatchIntervalMs: 500

    /// Number of inbox messages inspected per author-prefetch timer tick.
    readonly property int authorPrefetchBatchSize: 1

    /// Max recursion depth when walking JSON to extract author objects.
    readonly property int authorWalkMaxDepth: 8

    /// Automatic author enrichment runs in the background and intentionally
    /// avoids large detail endpoints so popup opening does not trigger this work.
    readonly property bool automaticAuthorPrefetchEnabled: true

    /// Default avatar URL pattern. Insert login and append ?size=128.
    readonly property int avatarDefaultSizePx: 128

    /// connect-timeout (seconds) for avatar image downloads via curl.
    readonly property string avatarDownloadConnectTimeoutSeconds: "10"

    /// max-time (seconds) for avatar image downloads via curl.
    readonly property string avatarDownloadMaxTimeSeconds: "30"

    /// Delay between built-in downloader attempts, bounded by the provider retry policy.
    readonly property int avatarDownloadRetryDelayMs: 1000

    /// Maximum number of times a RoundedAvatar retries loading after an error
    /// (e.g. transient network failure after system wakeup).
    readonly property int avatarImageMaxRetries: 3

    /// Base delay (ms) before the first retry; doubled for each subsequent
    /// attempt (exponential back-off).
    readonly property int avatarImageRetryBaseDelayMs: 1500

    /// Rendered resolution (width and height) used for preloaded avatar Image
    /// items.  Kept small to reduce memory and network bandwidth.
    readonly property int avatarPreloadSourceSizePx: 40

    // =========================================================================
    // Avatar / Image Cache
    // =========================================================================

    /// Maximum number of entries kept in the background avatar preload list.
    /// Prevents unbounded growth when a user has many distinct authors.
    readonly property int avatarPreloadTotalCacheLimit: 0

    /// Delay after inbox messages are applied before starting background
    /// author/avatar enrichment. Keeps startup focused on showing inbox counts
    /// and rows before lower-priority metadata work begins.
    readonly property int backgroundEnrichmentDelayMs: 3500

    /// Minimum pixel size of the bar-pill icon regardless of configured icon
    /// size.
    readonly property int barIconMinSizePx: 12

    /// Number of pixels subtracted from the configured icon size to size the
    /// bar-pill icon slightly smaller than surrounding text.
    readonly property int barIconSizeReductionPx: 4

    /// Name of the sub-directory inside the cache directory where avatar image
    /// files are stored.
    readonly property string cacheAvatarsSubdirectory: "avatars"

    /// Fallback cache directory path used when XDG_CACHE_HOME cannot be
    /// resolved at runtime.
    readonly property string cacheFallbackDirPath: "/tmp/dms-github-inbox-plugin"

    /// Name of the JSON metadata file stored inside the cache directory.
    readonly property string cacheFileName: "cache.json"

    // =========================================================================
    // Disk Cache
    // =========================================================================

    /// JSON cache file format version. Bump when structure changes.
    readonly property int cacheFormatVersion: 1

    /// Delay (ms) used to batch author-cache metadata before merging it into
    /// the disk payload.  This avoids one whole-map update per author result.
    readonly property int cacheMetadataFlushIntervalMs: 2000

    /// Sub-directory under the cache root for serialized object/cache metadata.
    readonly property string cacheObjectsSubdirectory: "objects"

    /// Directory name under XDG_CACHE_HOME for every cache artifact owned by
    /// this plugin.
    readonly property string cacheRootDirectoryName: "dms-github-inbox-plugin"

    /// Delay (ms) between the last cache-dirtying operation and the actual
    /// disk write, so that rapid updates get batched into one write.
    readonly property int cacheSaveDebounceMs: 2000

    // =========================================================================
    // Networking - curl Command Arguments
    // =========================================================================

    /// Maximum seconds curl waits when establishing a TCP connection.
    /// Passed as a string because it is spliced directly into the command array.
    readonly property string curlConnectTimeoutSeconds: "10"

    /// Maximum total seconds allowed for any single HTTP request.
    /// Passed as a string because it is spliced directly into the command array.
    readonly property string curlMaxTimeSeconds: "20"

    /// curl -w format string to extract the HTTP status code.
    readonly property string curlStatusCodeFormat: "%{http_code}"

    /// Backward-compatible name for existing perf breadcrumb guards.
    readonly property bool debugPerformanceLogging: verbosePerformanceLogging

    // =========================================================================
    // Desktop Notifications
    // =========================================================================

    /// Whether desktop notifications for new inbox messages are enabled by
    /// default (before the user toggles them off in settings).
    readonly property bool defaultEnableNotifications: true

    /// Default maximum number of inbox messages shown per repository group.
    readonly property int defaultGroupItemLimit: 10

    // =========================================================================
    // Settings - Default Values
    // =========================================================================

    /// Default poll interval persisted to settings, expressed in seconds.
    readonly property string defaultPollIntervalSetting: String(GitHubManager.properties.defaultPollIntervalSeconds)

    /// Default popup height expressed in message-row "height units".
    readonly property int defaultPopupHeightUnits: 15

    /// Default maximum number of lines rendered for an inbox message title.
    readonly property int defaultTitleLines: 2

    /// Minimum interval between done-state cache cleanup passes.
    readonly property real doneStateCleanupIntervalMs: 24 * 60 * 60 * 1000

    /// Age after which locally done thread entries can be removed from the
    /// object cache. Avatars are intentionally not cleaned by this policy.
    readonly property real doneStateRetentionMs: 60 * 24 * 60 * 60 * 1000

    /// Hard safety cap for dynamic GitHub inbox pagination. Refresh starts at
    /// one page and continues only until the fetched window covers the oldest
    /// currently loaded visible item, or until this cap is reached.
    readonly property int dynamicFetchMaxPages: GitHubManager.properties.maximumPageLimit

    /// Minimum interval between repeated background-refresh error notifications.
    readonly property int errorNotificationRepeatMs: 600000

    // =========================================================================
    // Internal State Keys
    // =========================================================================

    /// Object key used to store the fall-through expand/collapse default inside
    /// the expandedReposState map.
    readonly property string expandedStateDefaultKey: "__defaultExpanded"

    // =========================================================================
    // Payload Splitting Tokens
    // =========================================================================

    /// Sentinel string injected by curl (via -w) between successive inbox message
    /// page responses so the parser can split them without a boundary marker in
    /// the JSON itself.
    readonly property string fetchPayloadSplitToken: "__GH_PARTICIPATING_SPLIT__"

    /// Retain the compact selector's subdued accent instead of the filled theme default.
    readonly property real filterSelectionOpacity: 0.16

    /// Number of pages fetched on the first run, before there is a visible
    /// local inbox window to compare against.
    readonly property int firstRunFetchPageCount: GitHubManager.properties.firstRunPageLimit

    // =========================================================================
    // GitHub Web & API URLs
    // =========================================================================

    /// Root URL of the GitHub REST API v3.
    readonly property string githubApiBaseUrl: GitHubManager.properties.apiBaseUrl

    // =========================================================================
    // GitHub API URL Building
    // =========================================================================

    /// API path prefix for repository-scoped GitHub REST endpoints.
    readonly property string githubApiReposPrefix: GitHubManager.properties.apiBaseUrl + "/repos/"

    /// Value sent as the "X-GitHub-Api-Version" HTTP request header.
    readonly property string githubApiVersionHeader: GitHubManager.properties.apiVersion

    /// Base URL for GitHub avatar images. Works for both regular users and
    /// [bot] accounts (unlike github.com/LOGIN.png which 404s for bots).
    readonly property string githubAvatarsBaseUrl: GitHubManager.properties.avatarsBaseUrl

    /// URL of the GitHub favicon used as the primary icon in the status bar.
    readonly property string githubFaviconUrl: GitHubManager.properties.webBaseUrl + "/favicon.ico"

    // =========================================================================
    // Status Bar Icon
    // =========================================================================

    /// Opacity applied to the GitHub favicon/SVG icon in the bar pill.
    readonly property real githubIconBarOpacity: 0.74

    /// Canonical GitHub inbox messages list endpoint.
    readonly property string githubInboxApiUrl: GitHubManager.properties.apiBaseUrl + GitHubManager.properties.inboxPath

    /// API path for a specific notification thread. Append the thread ID.
    readonly property string githubThreadApiPrefix: GitHubManager.properties.apiBaseUrl + GitHubManager.properties.threadPath + "/"

    /// GitHub settings page where users create classic personal-access tokens.
    readonly property string githubTokenSettingsUrl: GitHubManager.properties.webBaseUrl + "/settings/tokens"

    /// Root URL of the GitHub web interface.
    readonly property string githubWebBaseUrl: GitHubManager.properties.webBaseUrl

    // =========================================================================
    // HTTP Headers & Status Codes
    // =========================================================================

    /// Value for the Accept header in GitHub API requests.
    readonly property string httpAcceptHeader: "application/vnd.github+json"

    /// Maximum HTTP status code (exclusive) that indicates a successful response.
    readonly property int httpSuccessMax: 300

    /// Minimum HTTP status code that indicates a successful response.
    readonly property int httpSuccessMin: 200

    /// Extra attempts for a GitHub inbox GET canceled at the HTTP/2 stream layer.

    // =========================================================================
    // Performance Debugging
    // =========================================================================

    /// Developer mode enables opt-in performance instrumentation. Keep this
    /// false for normal shell use so metrics/logging do not add UI-thread work.
    /// Public flag used by the plugin to enable profiling and development UI.
    readonly property bool isDevMode: false

    /// Maximum downloaded avatars propagated to live models in one UI tick.
    readonly property int localAvatarPropagationBatchSize: 16

    /// Delay used to batch local-avatar propagation into live QML models after
    /// curl finishes a background avatar download.
    readonly property int localAvatarPropagationDelayMs: 350

    /// Master switch for all plugin console output. Development mode is opt-in.
    readonly property bool loggingEnabled: isDevMode

    /// Maximum notification threads whose extra author metadata is prefetched
    /// automatically during one refresh. The automatic path fetches only the
    /// lightweight subject object, not large timeline/review expansions.
    readonly property int maxAuthorPrefetchMessagesPerRefresh: 300

    /// Maximum queued author-fetch requests retained at once.
    readonly property int maxAuthorRequestQueueLength: 160

    /// Maximum number of distinct API URLs bundled into one author-fetch curl
    /// invocation.  Limits the size of a single outbound network batch.
    readonly property int maxAuthorUrlsPerThreadFetch: 8

    // =========================================================================
    // Author Avatar & Label
    // =========================================================================

    /// Maximum number of authors shown in the author column per inbox message.
    /// Additional authors beyond this limit are silently dropped.
    readonly property int maxAuthorsDisplayedPerMessage: 3

    /// Maximum number of avatar downloads waiting behind active requests.
    readonly property int maxAvatarQueueLength: 500

    /// Maximum number of author-fetch curl requests in flight at the same time.
    readonly property int maxConcurrentAuthorFetches: GitHubManager.properties.maximumConcurrentRequests

    /// Maximum avatar downloads running at the same time.  Keep this modest:
    /// avatar work is background I/O, but every completed file still notifies QML.
    readonly property int maxConcurrentAvatarDownloads: GitHubManager.properties.maximumConcurrentRequests

    /// Maximum allowed value for the group item limit setting.
    readonly property int maxGroupItemLimit: 25

    /// Maximum allowed value for the popup height units setting.
    readonly property int maxPopupHeightUnits: 40

    /// Maximum allowed value for the title lines setting.
    readonly property int maxTitleLines: 6

    /// Pixel size of the icon glyph inside each action button.
    readonly property int messageActionButtonIconSizePx: 13

    /// Width and height (square) of each individual action button.
    readonly property int messageActionButtonSizePx: 22

    /// Offset from Theme.spacingXS between message action buttons.
    readonly property int messageActionButtonsSpacingDelta: 0

    /// Duration (ms) of the fade-in / fade-out animation for the action-button
    /// row triggered by hovering an inbox message row.
    readonly property int messageActionsFadeDurationMs: 100

    /// Total pixel height of the action-button overlay host item.
    readonly property int messageActionsHostHeightPx: 24

    /// Offset from Theme.spacingXS between the action-button overlay and the
    /// inbox message row border.
    readonly property int messageActionsHostMarginDelta: 0

    // =========================================================================
    // Inbox Message Row Hover Action Buttons
    // =========================================================================

    /// Total pixel width of the action-button overlay host item that sits in
    /// the bottom-left corner of an inbox message row.
    readonly property int messageActionsHostWidthPx: 48

    /// Offset from Theme.spacingXXS between author rows.
    readonly property int messageAuthorColumnItemSpacingDelta: 0

    /// Minimum pixel width of the author-list column to the right of the main
    /// info area.
    readonly property int messageAuthorColumnMinWidthPx: 72

    /// Preferred author avatar diameter and row height, relative to Theme.fontSizeMedium.
    /// Compact cards fit this down to preserve all three avatars and their padding.
    readonly property int messageAuthorRowHeightDelta: 12

    /// Fill opacity of the subject-type icon badge background tint.
    readonly property real messageIconBadgeBackgroundOpacity: 0.4

    /// Height of the rounded-rectangle badge behind the subject-type icon.
    readonly property int messageIconBadgeHeightPx: 24

    /// Offset from Theme.cornerRadius for the subject-type badge.
    readonly property int messageIconBadgeRadiusDelta: 1

    /// Width of the rounded-rectangle badge behind the subject-type icon.
    readonly property int messageIconBadgeWidthPx: 24

    /// Width of the left icon slot that contains the subject-type badge.
    readonly property int messageIconSlotWidthPx: 26

    /// Offset from Theme.spacingXS between title/metadata items.
    readonly property int messageMainInfoColumnSpacingDelta: 2

    /// Absolute minimum pixel width of the title/metadata column so it never
    /// becomes smaller than a comfortable reading width.
    readonly property int messageMainInfoMinWidthPx: 120

    /// Fraction of the row body (0-1) devoted to the title/metadata column.
    readonly property real messageMainInfoWidthRatio: 0.7

    /// Offset from Theme.fontSizeSmall for subject-type, reason, and time labels.
    readonly property int messageMetadataFontSizeDelta: -1
    readonly property real messageMetadataTextOpacity: 0.55

    /// Offset from Theme.spacingM below the author column when calculating
    /// the total row height.
    readonly property int messageRowAuthorColumnPaddingDelta: 2

    /// Width of the border rectangle drawn around each inbox message row card.
    readonly property int messageRowBorderWidthPx: 1

    /// Minimum title/metadata height: Theme.fontSizeMedium * 2 plus this delta.
    readonly property int messageRowContentMinHeightDelta: 12

    // =========================================================================
    // Inbox Message Row Layout
    // =========================================================================

    /// Minimum row height: Theme.fontSizeMedium * 3 plus this delta, ensuring
    /// tap targets stay large enough on touch displays.
    readonly property int messageRowMinHeightDelta: 30

    /// Offset from Theme.fontSizeMedium added per title line.
    readonly property int messageRowTitleLineHeightDelta: 2

    /// Fill opacity of the background tint applied to unread inbox message rows.
    readonly property real messageRowUnreadBackgroundOpacity: 0.10

    /// Opacity of the border drawn around unread inbox message rows.
    readonly property real messageRowUnreadBorderOpacity: 0.35

    /// Theme-derived opacity for repository/author labels and less prominent card metadata.
    readonly property real messageSecondaryTextOpacity: 0.75

    /// Pixel size of the subject-type icon glyph.
    readonly property int messageSubjectIconSizePx: 17

    // =========================================================================
    // API Request Sizing
    // =========================================================================

    /// Number of inbox messages requested per page from the GitHub API.
    readonly property int messagesApiPageSize: GitHubManager.properties.messagesPerPage

    /// Number of inbox message items sent in each worker-script chunk message
    /// so that the main thread processes results incrementally.
    readonly property int messagesParseChunkSize: 40

    // =========================================================================
    // Settings - Minimum / Maximum Bounds
    // =========================================================================

    /// Minimum allowed value for the group item limit setting.
    readonly property int minGroupItemLimit: 1

    /// Minimum acceptable poll interval in seconds; shorter values are clamped
    /// to this floor to avoid hammering the GitHub API.
    readonly property int minPollIntervalSeconds: GitHubManager.properties.minPollIntervalSeconds

    /// Minimum allowed value for the popup height units setting.
    readonly property int minPopupHeightUnits: 5

    /// Minimum allowed value for the title lines setting.
    readonly property int minTitleLines: 1

    /// Application name passed to dms notify via the -a flag.
    readonly property string notificationAppName: "GitHub Inbox"

    /// Maximum number of new inbox messages whose title is shown in the
    /// desktop-notification body. Larger batches use a generic message.
    readonly property int notificationDetailedMessageLimit: 2

    /// Notification expiry timeout in milliseconds passed to dms notify -t.
    readonly property int notificationExpireMs: 10000
    readonly property string openAuthorWebPageTooltipText: "Open author's web page"
    readonly property string openRepoWebPageTooltipText: "Open repo web page"

    /// Shared instruction for browser links, appended after full text when it is truncated.
    readonly property string openWebPageTooltipText: "Open web page"

    // =========================================================================
    // Plugin Identity
    // =========================================================================

    /// The DMS layer-namespace / plugin-ID registered with PluginComponent and
    /// PluginSettings.  Must match the value in plugin.json.
    readonly property string pluginNamespaceId: "githubInbox"

    // =========================================================================
    // Popout Window Layout
    // =========================================================================

    /// Nominal pixel width of the popout before the scale factor is applied.
    readonly property int popoutBaseWidthPx: 560

    /// Offset from Theme.fontSizeSmall for the refresh-error symbol.
    readonly property int popoutErrorBadgeFontSizeDelta: -3

    /// Background fill opacity of the filter bar container rectangle.
    readonly property real popoutFilterBackgroundOpacity: 0.80

    /// Offset from Theme.spacingS above the filter row.
    readonly property int popoutFilterBarVerticalPaddingDelta: -2

    /// Fixed pixel width of the "Participated" filter label.
    readonly property int popoutFilterParticipatedLabelWidthPx: 72

    /// Fixed pixel width of the "Read" filter label.
    readonly property int popoutFilterReadLabelWidthPx: 34

    // =========================================================================
    // Popout Filter Bar
    // =========================================================================

    /// Height of each segmented filter control (Read / Participation).
    readonly property int popoutFilterSegmentHeightPx: 24

    /// Offset from Theme.spacingS between a group edge and its messages.
    readonly property int popoutGroupContentHorizontalInsetDelta: 0

    /// Fixed pixel height allocated to each repository-group header row when
    /// estimating the required popout window height.
    readonly property int popoutGroupHeaderHeightPx: 38

    /// Offset from Theme.spacingXS for group-header leading content.
    readonly property int popoutGroupHeaderLeadingInsetDelta: 0

    /// Pixel size of the icon glyph placed inside each header action button.
    readonly property int popoutHeaderButtonIconSizePx: 18

    // =========================================================================
    // Popout Header Action Buttons
    // =========================================================================

    /// Width and height (square) of each icon button in the popout header.
    readonly property int popoutHeaderButtonSizePx: 28

    /// Offset from Theme.spacingS between popout header buttons.
    readonly property int popoutHeaderButtonSpacingDelta: -2

    /// Duration (ms) of the popout header button-row fade-in / fade-out
    /// animation triggered by hovering the header area.
    readonly property int popoutHeaderFadeDurationMs: 120

    /// Constant pixel padding added to the estimated content height when
    /// computing the popout window height.
    readonly property int popoutHeightBasePaddingPx: 180

    /// Maximum permitted popout window height in pixels.
    readonly property int popoutMaxHeightPx: 1200

    /// Minimum permitted popout window height in pixels.
    readonly property int popoutMinHeightPx: 260

    /// Size of the fallback "folder" icon shown when the repo avatar has not
    /// loaded yet.
    readonly property int popoutRepoAvatarFallbackIconSizePx: 18

    /// Offset from Theme.fontSizeSmall for the notification-count badge height.
    readonly property int popoutRepoCountBadgeHeightDelta: 6

    /// Offset from Theme.cornerRadius for notification-count badges.
    readonly property int popoutRepoCountBadgeRadiusDelta: -3

    /// Background opacity of the read-count badge.
    readonly property real popoutRepoCountBadgeReadOpacity: 0.20

    /// Background opacity of the unread-count badge.
    readonly property real popoutRepoCountBadgeUnreadOpacity: 0.18

    /// Offset from Theme.fontSizeSmall for notification-count badges.
    readonly property int popoutRepoCountFontSizeDelta: -2

    /// Width and height (square) of the "mark repo done" button in the group
    /// header.
    readonly property int popoutRepoDoneButtonSizePx: 20

    /// Size of the icon inside the "mark repo done" button.
    readonly property int popoutRepoDoneIconSizePx: 13

    /// Pixel size of the expand / collapse chevron icon in the group header.
    readonly property int popoutRepoExpandIconSizePx: 18

    /// Duration (ms) of the chevron rotation animation when a group is toggled.
    readonly property int popoutRepoExpandRotationDurationMs: 120

    // =========================================================================
    // Popout Repository Group Row
    // =========================================================================

    /// Offset from Theme.fontSizeMedium for the repository-group header height.
    readonly property int popoutRepoHeaderHeightDelta: 14

    /// Pixel height added per notification-title line in the popout height
    /// estimate, allowing taller rows to inflate the window proportionally.
    readonly property int popoutTitleLineHeightContributionPx: 6

    /// Fraction applied to popoutBaseWidthPx to produce the final popout
    /// width, allowing extra whitespace around the panel.
    readonly property real popoutWidthScale: 0.85

    /// When true, log every profiled operation, not only slow ones.
    readonly property bool profileLogAllOperations: isDevMode

    /// Enables duration profiles for slow/anomalous QML-side operations.
    readonly property bool profileLoggingEnabled: isDevMode

    /// Duration threshold for profile logs. Values above this are suspicious
    /// because they can cost a visible frame on the shell UI thread.
    readonly property int profileSlowOperationThresholdMs: 12

    /// Background work that remains busy longer than this is assumed stale. This
    /// is intentionally higher than curl timeouts because author/avatar queues
    /// can legitimately keep working for several batches.
    readonly property int refreshBusyStaleMs: 300000

    /// External commands required for the plugin's full operation.
    readonly property var requiredCommands: ["bash", "curl", "secret-tool", "jq", "file", "nice", "cp", "find", "mkdir", "cat", "rm", "env", "sleep"]

    /// Minimum delay between resource-ready UI notifications. Avatar/author
    /// workers may finish several resources close together; the view consumes
    /// those updates in batches instead of re-rendering for each file.
    readonly property int resourceReadyFlushIntervalMs: 1000

    /// Fraction of the stats table width allocated to the "Avg sec" column.
    readonly property real settingsStatsAvgDurationColumnWidthRatio: 0.205

    /// Fraction of the stats table width allocated to the "Calls" column.
    readonly property real settingsStatsCallsColumnWidthRatio: 0.205

    /// Offset from Theme.fontSizeSmall for each API stats data row.
    readonly property int settingsStatsDataRowHeightDelta: 8

    /// Offset from Theme.fontSizeSmall for API stats table text.
    readonly property int settingsStatsFontSizeDelta: -2

    // =========================================================================
    // Settings Page UI
    // =========================================================================

    /// Offset from Theme.fontSizeSmall for the API stats header row.
    readonly property int settingsStatsHeaderRowHeightDelta: 6

    /// Fraction of the stats table width allocated to the "Refreshes" column.
    readonly property real settingsStatsRefreshesColumnWidthRatio: 0.21

    /// Offset from Theme.spacingXXS between API stats table rows.
    readonly property int settingsStatsRowSpacingDelta: 0

    /// Fraction of the stats table width allocated to the "Scope" column.
    readonly property real settingsStatsScopeColumnWidthRatio: 0.38

    /// Number of cached author-thread entries inspected per startup recovery
    /// tick for missing avatar files.
    readonly property int startupMissingInfoScanBatchSize: 2

    /// Delay between startup recovery ticks.  This keeps cache-repair work off
    /// the first render frame and lets avatar downloads enter their own queue.
    readonly property int startupMissingInfoScanIntervalMs: 1000

    /// How often (ms) the stats singleton prunes entries that have fallen outside
    /// the one-hour rolling window.
    readonly property int statsHourlyPruneIntervalMs: 60000

    // =========================================================================
    // API Call Statistics
    // =========================================================================

    /// Refresh durations longer than this threshold are assumed to be caused by
    /// the machine suspending mid-refresh and are excluded from averages (2 min).
    readonly property int statsMaxReasonableRefreshDurationMs: 120000

    /// Width (ms) of the rolling window used for the "last hour" statistics
    /// bucket.
    readonly property int statsOneHourWindowMs: 3600000

    /// Minimum delayed timer gap logged as a UI-thread stall in DevMode.
    readonly property int uiStallLogThresholdMs: 750

    /// How often the UI-thread stall probe checks for delayed timer delivery.
    readonly property int uiStallProbeIntervalMs: 250

    /// Maximum unread count displayed as a plain number; anything higher shows
    /// as "999+".
    readonly property int unreadCountDisplayMax: 999

    /// Set to true to emit verbose timing breadcrumbs. Keep this false during
    /// normal diagnosis because log spam can itself slow the shell at startup.
    readonly property bool verbosePerformanceLogging: isDevMode

    /// Number of parsed inbox messages applied to the visible popout model per
    /// UI tick.  Keeps startup/cache refreshes from rebuilding delegates in one
    /// long main-thread turn.
    readonly property int viewApplyChunkSize: 5

    /// How often (ms) the view-apply timer ticks while draining pending
    /// inbox message chunks into the visible list.
    readonly property int viewApplyTimerIntervalMs: 16

    /// A UI timer gap above this value usually means the machine slept. If any
    /// network worker is still marked busy after such a gap, reset its runtime
    /// state so future refreshes are not blocked forever.
    readonly property int wakeRefreshRecoveryGapMs: 60000
}
