// Constants.qml - Central registry of every hardcoded value used by the GitHub Inbox plugin.
//
// All files in this module reference values through this singleton so that a change
// to any magic number, URL, or token only needs to be made in one place.
//
// QML usage:   Constants.SOME_CONSTANT   (no import needed - registered in qmldir)
// JS  usage:   see JS/GitHubConstants.js (mirrored subset; loaded via importScripts)

pragma Singleton

import QtQuick

QtObject {

    // =========================================================================
    // Plugin Identity
    // =========================================================================

    /// The DMS layer-namespace / plugin-ID registered with PluginComponent and
    /// PluginSettings.  Must match the value in plugin.json.
    readonly property string pluginNamespaceId: "github-inbox"


    // =========================================================================
    // GitHub Web & API URLs
    // =========================================================================

    /// Root URL of the GitHub REST API v3.
    readonly property string githubApiBaseUrl: "https://api.github.com"

    /// Root URL of the GitHub web interface.
    readonly property string githubWebBaseUrl: "https://github.com"

    /// Base URL for GitHub avatar images. Works for both regular users and
    /// [bot] accounts (unlike github.com/LOGIN.png which 404s for bots).
    readonly property string githubAvatarsBaseUrl: "https://avatars.githubusercontent.com"

    /// Value sent as the "X-GitHub-Api-Version" HTTP request header.
    readonly property string githubApiVersionHeader: "2022-11-28"

    /// Canonical GitHub inbox messages list endpoint.
    readonly property string githubInboxApiUrl: "https://api.github.com/notifications"

    /// GitHub settings page where users create classic personal-access tokens.
    readonly property string githubTokenSettingsUrl: "https://github.com/settings/tokens"

    /// URL of the GitHub favicon used as the primary icon in the status bar.
    readonly property string githubFaviconUrl: "https://github.com/favicon.ico"


    // =========================================================================
    // Payload Splitting Tokens
    // =========================================================================

    /// Sentinel string injected by curl (via -w) between successive inbox message
    /// page responses so the parser can split them without a boundary marker in
    /// the JSON itself.
    readonly property string fetchPayloadSplitToken: "__GH_PARTICIPATING_SPLIT__"

    /// Sentinel string injected by curl between successive author-detail API
    /// responses gathered in a single curl invocation.
    readonly property string authorPayloadSplitToken: "__GH_AUTHOR_SPLIT__"


    // =========================================================================
    // Networking - curl Command Arguments
    // =========================================================================

    /// Maximum seconds curl waits when establishing a TCP connection.
    /// Passed as a string because it is spliced directly into the command array.
    readonly property string curlConnectTimeoutSeconds: "10"

    /// Maximum total seconds allowed for any single HTTP request.
    /// Passed as a string because it is spliced directly into the command array.
    readonly property string curlMaxTimeSeconds: "20"


    // =========================================================================
    // HTTP Headers & Status Codes
    // =========================================================================

    /// Value for the Accept header in GitHub API requests.
    readonly property string httpAcceptHeader: "application/vnd.github+json"

    /// Minimum HTTP status code that indicates a successful response.
    readonly property int httpSuccessMin: 200

    /// Maximum HTTP status code (exclusive) that indicates a successful response.
    readonly property int httpSuccessMax: 300

    /// curl -w format string to extract the HTTP status code.
    readonly property string curlStatusCodeFormat: "%{http_code}"


    // =========================================================================
    // GitHub API URL Building
    // =========================================================================

    /// API path prefix for repository-scoped GitHub REST endpoints.
    readonly property string githubApiReposPrefix: "https://api.github.com/repos/"

    /// API path for a specific notification thread. Append the thread ID.
    readonly property string githubThreadApiPrefix: "https://api.github.com/notifications/threads/"

    /// Default avatar URL pattern. Insert login and append ?size=128.
    readonly property int avatarDefaultSizePx: 128

    /// Max recursion depth when walking JSON to extract author objects.
    readonly property int authorWalkMaxDepth: 8


    // =========================================================================
    // API Request Sizing
    // =========================================================================

    /// Number of inbox messages requested per page from the GitHub API.
    readonly property int messagesApiPageSize: 50

    /// Query string appended to author-detail sub-requests to fetch up to 100
    /// items per page and avoid unnecessary pagination.
    readonly property string authorFetchPerPageQuery: "per_page=100"

    /// Maximum number of distinct API URLs bundled into one author-fetch curl
    /// invocation.  Limits the size of a single outbound network batch.
    readonly property int maxAuthorUrlsPerThreadFetch: 16

    /// Maximum number of author-fetch curl requests in flight at the same time.
    readonly property int maxConcurrentAuthorFetches: 3

    /// Number of inbox message items sent in each worker-script chunk message
    /// so that the main thread processes results incrementally.
    readonly property int messagesParseChunkSize: 80


    // =========================================================================
    // Avatar / Image Cache
    // =========================================================================

    /// Maximum number of entries kept in the background avatar preload list.
    /// Prevents unbounded growth when a user has many distinct authors.
    readonly property int avatarPreloadTotalCacheLimit: 500

    /// Rendered resolution (width and height) used for preloaded avatar Image
    /// items.  Kept small to reduce memory and network bandwidth.
    readonly property int avatarPreloadSourceSizePx: 64

    /// Maximum number of times a RoundedAvatar retries loading after an error
    /// (e.g. transient network failure after system wakeup).
    readonly property int avatarImageMaxRetries: 3

    /// Base delay (ms) before the first retry; doubled for each subsequent
    /// attempt (exponential back-off).
    readonly property int avatarImageRetryBaseDelayMs: 1500


    // =========================================================================
    // Disk Cache
    // =========================================================================

    /// JSON cache file format version. Bump when structure changes.
    readonly property int cacheFormatVersion: 1

    /// Default sub-directory name under XDG_CACHE_HOME for the plugin cache.
    readonly property string cacheSubdirectory: "github-inbox"

    /// Default freshness TTL for the disk cache in minutes.  Data older than
    /// this is considered stale and a background re-fetch is started immediately.
    readonly property int defaultCacheTtlMinutes: 60

    /// Minimum allowed cache TTL in minutes (settings slider floor).
    readonly property int minCacheTtlMinutes: 5

    /// Maximum allowed cache TTL in minutes (settings slider ceiling).
    readonly property int maxCacheTtlMinutes: 1440

    /// Delay (ms) between the last cache-dirtying operation and the actual
    /// disk write, so that rapid updates get batched into one write.
    readonly property int cacheSaveDebounceMs: 2000

    /// connect-timeout (seconds) for avatar image downloads via curl.
    readonly property string avatarDownloadConnectTimeoutSeconds: "10"

    /// max-time (seconds) for avatar image downloads via curl.
    readonly property string avatarDownloadMaxTimeSeconds: "30"

    /// Name of the JSON metadata file stored inside the cache directory.
    readonly property string cacheFileName: "cache.json"

    /// Name of the sub-directory inside the cache directory where avatar image
    /// files are stored.
    readonly property string cacheAvatarsSubdirectory: "avatars"

    /// Fallback cache directory path used when XDG_CACHE_HOME cannot be
    /// resolved at runtime.
    readonly property string cacheFallbackDirPath: "/tmp/github-inbox-cache"


    // =========================================================================
    // Settings - Default Values
    // =========================================================================

    /// Default poll interval persisted to settings, expressed in seconds.
    readonly property string defaultPollIntervalSetting: "120"

    /// Minimum acceptable poll interval in seconds; shorter values are clamped
    /// to this floor to avoid hammering the GitHub API.
    readonly property int minPollIntervalSeconds: 60

    /// Default maximum number of inbox messages shown per repository group.
    readonly property int defaultGroupItemLimit: 25

    /// Default number of API pages fetched per refresh cycle.
    readonly property int defaultFetchPageCount: 3

    /// Default popup height expressed in message-row "height units".
    readonly property int defaultPopupHeightUnits: 10

    /// Default maximum number of lines rendered for an inbox message title.
    readonly property int defaultTitleLines: 2


    // =========================================================================
    // Settings - Minimum / Maximum Bounds
    // =========================================================================

    /// Minimum allowed value for the group item limit setting.
    readonly property int minGroupItemLimit: 1

    /// Maximum allowed value for the group item limit setting.
    readonly property int maxGroupItemLimit: 25

    /// Minimum allowed value for the fetch page count setting.
    readonly property int minFetchPageCount: 1

    /// Maximum allowed value for the fetch page count setting.
    readonly property int maxFetchPageCount: 10

    /// Minimum allowed value for the popup height units setting.
    readonly property int minPopupHeightUnits: 5

    /// Maximum allowed value for the popup height units setting.
    readonly property int maxPopupHeightUnits: 40

    /// Minimum allowed value for the title lines setting.
    readonly property int minTitleLines: 1

    /// Maximum allowed value for the title lines setting.
    readonly property int maxTitleLines: 6


    // =========================================================================
    // API Call Statistics
    // =========================================================================

    /// Refresh durations longer than this threshold are assumed to be caused by
    /// the machine suspending mid-refresh and are excluded from averages (2 min).
    readonly property int statsMaxReasonableRefreshDurationMs: 120000

    /// How often (ms) the stats singleton prunes entries that have fallen outside
    /// the one-hour rolling window.
    readonly property int statsHourlyPruneIntervalMs: 60000

    /// Width (ms) of the rolling window used for the "last hour" statistics
    /// bucket.
    readonly property int statsOneHourWindowMs: 3600000


    // =========================================================================
    // Internal State Keys
    // =========================================================================

    /// Object key used to store the fall-through expand/collapse default inside
    /// the expandedReposState map.
    readonly property string expandedStateDefaultKey: "__defaultExpanded"

    /// How often (ms) the view-apply timer ticks while draining pending
    /// inbox message chunks into the visible list.
    readonly property int viewApplyTimerIntervalMs: 8

    /// Maximum unread count displayed as a plain number; anything higher shows
    /// as "999+".
    readonly property int unreadCountDisplayMax: 999


    // =========================================================================
    // Popout Window Layout
    // =========================================================================

    /// Nominal pixel width of the popout before the scale factor is applied.
    readonly property int popoutBaseWidthPx: 560

    /// Fraction applied to popoutBaseWidthPx to produce the final popout
    /// width, allowing extra whitespace around the panel.
    readonly property real popoutWidthScale: 0.85

    /// Fixed pixel height allocated to each repository-group header row when
    /// estimating the required popout window height.
    readonly property int popoutGroupHeaderHeightPx: 38

    /// Pixel height added per notification-title line in the popout height
    /// estimate, allowing taller rows to inflate the window proportionally.
    readonly property int popoutTitleLineHeightContributionPx: 6

    /// Constant pixel padding added to the estimated content height when
    /// computing the popout window height.
    readonly property int popoutHeightBasePaddingPx: 180

    /// Minimum permitted popout window height in pixels.
    readonly property int popoutMinHeightPx: 260

    /// Maximum permitted popout window height in pixels.
    readonly property int popoutMaxHeightPx: 1200


    // =========================================================================
    // Popout Header Action Buttons
    // =========================================================================

    /// Width and height (square) of each icon button in the popout header.
    readonly property int popoutHeaderButtonSizePx: 28

    /// Corner radius of individual popout header icon buttons.
    readonly property int popoutHeaderButtonRadiusPx: 14

    /// Spacing between adjacent buttons in the popout header button row.
    readonly property int popoutHeaderButtonSpacingPx: 6

    /// Duration (ms) of the popout header button-row fade-in / fade-out
    /// animation triggered by hovering the header area.
    readonly property int popoutHeaderFadeDurationMs: 120

    /// Duration (ms) of one complete rotation of the refresh-spinner icon
    /// while a fetch or operation is in progress.
    readonly property int popoutRefreshIconSpinDurationMs: 800

    /// Pixel size of the icon glyph placed inside each header action button.
    readonly property int popoutHeaderButtonIconSizePx: 18

    /// Background opacity of header action buttons at rest (not hovered).
    readonly property real popoutHeaderButtonBackgroundOpacity: 0.85

    /// Opacity of the primary-colour hover tint on header action buttons.
    readonly property real popoutHeaderButtonHoverTintOpacity: 0.15


    // =========================================================================
    // Popout Repository Group Row
    // =========================================================================

    /// Height of the repository-group header row.
    readonly property int popoutRepoHeaderHeightPx: 28

    /// Width and height (square) of the repo-owner avatar shown in the group
    /// header.
    readonly property int popoutRepoAvatarSizePx: 20

    /// Size of the fallback "folder" icon shown when the repo avatar has not
    /// loaded yet.
    readonly property int popoutRepoAvatarFallbackIconSizePx: 18

    /// Height of the notification-count badge pill in the group header.
    readonly property int popoutRepoCountBadgeHeightPx: 18

    /// Corner radius of the notification-count badge pill.
    readonly property int popoutRepoCountBadgeRadiusPx: 9

    /// Font size of the count text inside the count badge.
    readonly property int popoutRepoCountFontSizePx: 10

    /// Pixel size of the expand / collapse chevron icon in the group header.
    readonly property int popoutRepoExpandIconSizePx: 18

    /// Duration (ms) of the chevron rotation animation when a group is toggled.
    readonly property int popoutRepoExpandRotationDurationMs: 120

    /// Width and height (square) of the "mark repo done" button in the group
    /// header.
    readonly property int popoutRepoDoneButtonSizePx: 20

    /// Corner radius of the "mark repo done" button.
    readonly property int popoutRepoDoneButtonRadiusPx: 10

    /// Size of the icon inside the "mark repo done" button.
    readonly property int popoutRepoDoneIconSizePx: 13

    /// Background opacity of the unread-count badge.
    readonly property real popoutRepoCountBadgeUnreadOpacity: 0.18

    /// Background opacity of the read-count badge.
    readonly property real popoutRepoCountBadgeReadOpacity: 0.20


    // =========================================================================
    // Popout Filter Bar
    // =========================================================================

    /// Height of each segmented filter control (Read / Participation).
    readonly property int popoutFilterSegmentHeightPx: 24

    /// Minimum pixel width of each segmented filter control.
    readonly property int popoutFilterSegmentMinWidthPx: 96

    /// Maximum pixel width of each segmented filter control.
    readonly property int popoutFilterSegmentMaxWidthPx: 132

    /// Fixed pixel width of the "Read" filter label.
    readonly property int popoutFilterReadLabelWidthPx: 34

    /// Fixed pixel width of the "Participated" filter label.
    readonly property int popoutFilterParticipatedLabelWidthPx: 72

    /// Background fill opacity of the filter bar container rectangle.
    readonly property real popoutFilterBackgroundOpacity: 0.80

    /// Fill opacity of the tint shown on the currently active filter segment.
    readonly property real popoutFilterActiveTintOpacity: 0.22

    /// Vertical padding (px) above the filter row inside the bar.
    readonly property int popoutFilterBarVerticalPaddingPx: 6


    // =========================================================================
    // Popout Scroll Indicator
    // =========================================================================

    /// Width of the thin scroll-position indicator strip on the right edge of
    /// the notification list.
    readonly property int popoutScrollIndicatorWidthPx: 4

    /// Corner radius of the scroll thumb rectangle.
    readonly property int popoutScrollIndicatorRadiusPx: 2

    /// Minimum pixel height of the scroll thumb so it stays visible even when
    /// content is very long.
    readonly property int popoutScrollIndicatorMinHeightPx: 20

    /// Opacity of the scroll thumb while the list is actively being scrolled.
    readonly property real popoutScrollIndicatorActiveOpacity: 0.8

    /// Opacity of the scroll thumb when the list is at rest.
    readonly property real popoutScrollIndicatorIdleOpacity: 0.4

    /// Duration (ms) of the scroll thumb opacity fade transition.
    readonly property int popoutScrollIndicatorFadeDurationMs: 200


    // =========================================================================
    // Inbox Message Row Layout
    // =========================================================================

    /// Minimum row height regardless of content, ensuring tap targets stay
    /// large enough on touch displays.
    readonly property int messageRowMinHeightPx: 72

    /// Minimum pixel height of the title/metadata content area inside a row.
    readonly property int messageRowContentMinHeightPx: 40

    /// Pixel height contribution added per title line when sizing a row.
    readonly property int messageRowTitleLineHeightPx: 16

    /// Extra vertical padding applied below the author column when calculating
    /// the total row height.
    readonly property int messageRowAuthorColumnPaddingPx: 14

    /// Height of each individual author entry row within an inbox message row.
    readonly property int messageAuthorRowHeightPx: 26

    /// Width of the left icon slot that contains the subject-type badge.
    readonly property int messageIconSlotWidthPx: 26

    /// Width of the rounded-rectangle badge behind the subject-type icon.
    readonly property int messageIconBadgeWidthPx: 24

    /// Height of the rounded-rectangle badge behind the subject-type icon.
    readonly property int messageIconBadgeHeightPx: 24

    /// Corner radius of the subject-type icon badge.
    readonly property int messageIconBadgeRadiusPx: 13

    /// Pixel size of the subject-type icon glyph.
    readonly property int messageSubjectIconSizePx: 17

    /// Fraction of the row body (0-1) devoted to the title/metadata column.
    readonly property real messageMainInfoWidthRatio: 0.7

    /// Absolute minimum pixel width of the title/metadata column so it never
    /// becomes smaller than a comfortable reading width.
    readonly property int messageMainInfoMinWidthPx: 120

    /// Font pixel size of the subject-type, reason, and timestamp labels.
    readonly property int messageMetadataFontSizePx: 12

    /// Vertical spacing (px) between items in the title/metadata column.
    readonly property int messageMainInfoColumnSpacingPx: 3

    /// Minimum pixel width of the author-list column to the right of the main
    /// info area.
    readonly property int messageAuthorColumnMinWidthPx: 72

    /// Vertical spacing between individual author entry rows.
    readonly property int messageAuthorColumnItemSpacingPx: 2

    /// Fill opacity of the background tint applied to unread inbox message rows.
    readonly property real messageRowUnreadBackgroundOpacity: 0.10

    /// Opacity of the border drawn around unread inbox message rows.
    readonly property real messageRowUnreadBorderOpacity: 0.35

    /// Width of the border rectangle drawn around each inbox message row card.
    readonly property int messageRowBorderWidthPx: 1

    /// Fill opacity of the subject-type icon badge background tint.
    readonly property real messageIconBadgeBackgroundOpacity: 0.4


    // =========================================================================
    // Author Avatar & Label
    // =========================================================================

    /// Maximum number of authors shown in the author column per inbox message.
    /// Additional authors beyond this limit are silently dropped.
    readonly property int maxAuthorsDisplayedPerMessage: 3

    /// Width and height (square) of the circular author avatar canvas.
    readonly property int authorAvatarSizePx: 24

    /// Font pixel size of the author login / display-name label beside the
    /// avatar.
    readonly property int authorNameFontSizePx: 11

    /// Minimum pixel width of the author name label to avoid collapsed text.
    readonly property int authorNameMinWidthPx: 28

    /// Size of the "person" fallback icon shown when no avatar URL is available.
    readonly property int authorAvatarFallbackIconSizePx: 12


    // =========================================================================
    // Inbox Message Row Hover Action Buttons
    // =========================================================================

    /// Total pixel width of the action-button overlay host item that sits in
    /// the top-right corner of an inbox message row.
    readonly property int messageActionsHostWidthPx: 74

    /// Total pixel height of the action-button overlay host item.
    readonly property int messageActionsHostHeightPx: 24

    /// Right and top margin (px) between the action-button overlay and the
    /// inbox message row border.
    readonly property int messageActionsHostMarginPx: 4

    /// Width and height (square) of each individual action button.
    readonly property int messageActionButtonSizePx: 22

    /// Corner radius of each action button rectangle.
    readonly property int messageActionButtonRadiusPx: 11

    /// Pixel size of the icon glyph inside each action button.
    readonly property int messageActionButtonIconSizePx: 13

    /// Gap (px) between adjacent action buttons.
    readonly property int messageActionButtonsSpacingPx: 4

    /// Background opacity of action button rectangles at rest.
    readonly property real messageActionButtonBgOpacity: 0.9

    /// Duration (ms) of the fade-in / fade-out animation for the action-button
    /// row triggered by hovering an inbox message row.
    readonly property int messageActionsFadeDurationMs: 100


    // =========================================================================
    // Settings Page UI
    // =========================================================================

    /// Pixel height of the GitHub token text-input field.
    readonly property int settingsTokenFieldHeightPx: 42

    /// Width and height (square) of the token-visibility toggle button.
    readonly property int settingsVisibilityButtonSizePx: 30

    /// Corner radius of the token-visibility toggle button.
    readonly property int settingsVisibilityButtonRadiusPx: 15

    /// Right margin between the visibility button and the token-field edge.
    readonly property int settingsVisibilityButtonRightMarginPx: 5

    /// Pixel size of the eye icon inside the token-visibility toggle button.
    readonly property int settingsVisibilityIconSizePx: 18

    /// Total height of a labelled slider setting item (label row + track row).
    readonly property int settingsSliderItemHeightPx: 52

    /// Height of the slider groove / track rectangle.
    readonly property int settingsSliderTrackHeightPx: 4

    /// Corner radius of the slider groove / track rectangle.
    readonly property int settingsSliderTrackRadiusPx: 2

    /// Height of the interactive slider hit-area that encompasses the thumb.
    readonly property int settingsSliderKnobAreaHeightPx: 24

    /// Width and height (square) of the slider thumb handle.
    readonly property int settingsSliderHandleSizePx: 18

    /// Corner radius of the slider thumb handle.
    readonly property int settingsSliderHandleRadiusPx: 9

    /// Border width drawn around the slider thumb handle.
    readonly property int settingsSliderHandleBorderWidthPx: 2

    /// Vertical padding (px) added on each side of the slider hit-area to
    /// increase the touch / click target without changing the visual size.
    readonly property int settingsSliderTouchExpansionPx: 8

    /// Vertical spacing between the slider label row and the track row.
    readonly property int settingsSliderColumnSpacingPx: 4

    /// Height of the column-header row in the API stats table.
    readonly property int settingsStatsHeaderRowHeightPx: 18

    /// Height of each data row in the API stats table.
    readonly property int settingsStatsDataRowHeightPx: 20

    /// Font pixel size of all text inside the API stats table.
    readonly property int settingsStatsFontSizePx: 10

    /// Duration (ms) of the expand / collapse animation for the API stats
    /// section.
    readonly property int settingsStatsExpandAnimationDurationMs: 150

    /// Fraction of the stats table width allocated to the "Scope" column.
    readonly property real settingsStatsScopeColumnWidthRatio: 0.38

    /// Fraction of the stats table width allocated to the "Calls" column.
    readonly property real settingsStatsCallsColumnWidthRatio: 0.205

    /// Fraction of the stats table width allocated to the "Avg sec" column.
    readonly property real settingsStatsAvgDurationColumnWidthRatio: 0.205

    /// Fraction of the stats table width allocated to the "Refreshes" column.
    readonly property real settingsStatsRefreshesColumnWidthRatio: 0.21


    // =========================================================================
    // Status Bar Icon
    // =========================================================================

    /// Opacity applied to the GitHub favicon/SVG icon in the bar pill.
    readonly property real githubIconBarOpacity: 0.74

    /// Minimum pixel size of the bar-pill icon regardless of configured icon
    /// size.
    readonly property int barIconMinSizePx: 12

    /// Number of pixels subtracted from the configured icon size to size the
    /// bar-pill icon slightly smaller than surrounding text.
    readonly property int barIconSizeReductionPx: 4


    // =========================================================================
    // Settings Page - Additional Values
    // =========================================================================

    /// Height of the outer Item container wrapping the token-field column
    /// (label + input field).
    readonly property int settingsTokenItemHeightPx: 72

    /// Background-fill opacity of the token-visibility toggle button on hover.
    readonly property real settingsButtonHoverOpacity: 0.16


    // =========================================================================
    // Desktop Notifications
    // =========================================================================

    /// Whether desktop notifications for new inbox messages are enabled by
    /// default (before the user toggles them off in settings).
    readonly property bool defaultEnableNotifications: true

    /// Application name passed to notify-send via the -a flag.
    readonly property string notificationAppName: "GitHub Inbox"

    /// Maximum number of message lines shown in a single notification body.
    readonly property int notificationMaxLines: 3

    /// Notification expiry timeout in milliseconds passed to notify-send -t.
    readonly property int notificationExpireMs: 10000

    // =========================================================================
    // Performance Debugging
    // =========================================================================

    /// Set to true to emit timing breadcrumbs to journalctl during startup.
    readonly property bool debugPerformanceLogging: false
}
