// InboxPreferencesService.qml - normalized, plugin-backed widget preferences.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: preferences

    property string clearCacheRequestFlag: pluginData.clearCacheRequested || ""
    property bool enableNotifications: providerApi.pluginDataBool(pluginData.enableNotifications, GitHubConstants.defaultEnableNotifications)
    property int groupItemLimit: boundedInteger(pluginData.groupItemLimit, GitHubConstants.defaultGroupItemLimit, GitHubConstants.minGroupItemLimit, GitHubConstants.maxGroupItemLimit)
    property string groupingMode: normalizeGroupingMode(pluginData.groupingMode || "repo")
    property bool loadAuthorInfo: providerApi.pluginDataBool(pluginData.loadAuthorInfo, true)
    property string participationFilter: normalizeTriStateFilter(pluginData.participationFilter || "both")
    property var pluginData: ({})
    property var pluginService: null
    property int pollIntervalMs: providerApi.pollIntervalMs(pluginData.pollInterval, GitHubManager.properties.defaultPollIntervalSeconds, GitHubManager.properties.minPollIntervalSeconds)
    property real popoutHeight: {
        let groups = Math.max(GitHubConstants.minPopupHeightUnits, popupHeightUnits);
        let perGroup = GitHubConstants.popoutGroupHeaderHeightPx + Math.max(1, titleLines) * GitHubConstants.popoutTitleLineHeightContributionPx;
        let estimated = groups * perGroup + GitHubConstants.popoutHeightBasePaddingPx;
        return Math.max(GitHubConstants.popoutMinHeightPx, Math.min(GitHubConstants.popoutMaxHeightPx, estimated));
    }
    property int popupHeightUnits: {
        let value = pluginData.popupHeight;
        if (value === undefined || value === "")
            value = pluginData.popupItems || GitHubConstants.defaultPopupHeightUnits;
        return boundedInteger(value, GitHubConstants.defaultPopupHeightUnits, GitHubConstants.minPopupHeightUnits, GitHubConstants.maxPopupHeightUnits);
    }
    property var providerApi: null
    property string readFilter: normalizeTriStateFilter(pluginData.readFilter || "both")
    property int titleLines: boundedInteger(pluginData.titleLines, GitHubConstants.defaultTitleLines, GitHubConstants.minTitleLines, GitHubConstants.maxTitleLines)

    // Clamp persisted numeric preferences before they reach layout or request configuration.
    function boundedInteger(value, fallback, minimum, maximum) {
        let parsed = parseInt(value);
        if (isNaN(parsed))
            return fallback;
        return Math.max(minimum, Math.min(maximum, parsed));
    }
    // Fall back to a supported mode rather than retaining an unknown saved value.
    function normalizeGroupingMode(value) {
        return String(value || "") === "date" ? "date" : "repo";
    }
    // Keep persisted filter state within the supported yes/no/both domain.
    function normalizeTriStateFilter(value) {
        let normalized = String(value || "").toLowerCase();
        return normalized === "yes" || normalized === "no" ? normalized : "both";
    }
    // Delegate a preference write to the host only after its service is attached.
    function persist(key, value) {
        if (pluginService)
            pluginService.savePluginData(GitHubConstants.pluginNamespaceId, key, value);
    }
    // Persist a changed mode without writing again for an unchanged selection.
    function setGroupingMode(value) {
        let nextValue = normalizeGroupingMode(value);
        if (groupingMode === nextValue)
            return;
        groupingMode = nextValue;
        persist("groupingMode", nextValue);
    }
    // Persist only a normalized participation selection.
    function setParticipationFilter(value) {
        let nextValue = normalizeTriStateFilter(value);
        if (participationFilter === nextValue)
            return;
        participationFilter = nextValue;
        persist("participationFilter", nextValue);
    }
    // Persist only a normalized read selection.
    function setReadFilter(value) {
        let nextValue = normalizeTriStateFilter(value);
        if (readFilter === nextValue)
            return;
        readFilter = nextValue;
        persist("readFilter", nextValue);
    }
}
