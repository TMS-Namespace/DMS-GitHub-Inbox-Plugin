// InboxPopoutContent.qml - connects inbox presentation events to plugin services.

pragma ComponentBehavior: Bound

import QtQuick
import ".."

InboxPopoutView {
    id: content

    property var authorRequestCallback: null
    property var closePopoutCallback: null
    property var openSettingsCallback: null
    property var operationService: null
    property var persistExpandedDateGroupsCallback: null
    property var persistExpandedReposCallback: null
    property var preferencesService: null
    property var refreshCallback: null
    property var visibilityChangedCallback: null

    onCloseRequested: {
        if (closePopoutCallback)
            closePopoutCallback();
    }
    onGroupingModeChangedByUser: function (value) {
        preferencesService.setGroupingMode(value);
    }
    onMarkAllRead: operationService.markAllAsRead()
    onMarkDateGroupDone: function (items) {
        operationService.markThreadsDone(items);
    }
    onMarkDateGroupRead: function (items) {
        operationService.markThreadsAsRead(items);
    }
    onMarkRepoDone: function (items) {
        operationService.markThreadsDone(items);
    }
    onMarkRepoRead: function (items) {
        operationService.markThreadsAsRead(items);
    }
    onMarkThreadDone: function (threadId) {
        operationService.markThreadDone(threadId);
    }
    onMarkThreadRead: function (threadId) {
        operationService.markThreadAsRead(threadId);
    }
    onMarkThreadReadAfterOpen: function (threadId) {
        operationService.markThreadReadAfterOpen(threadId);
    }
    onMarkThreadUnread: function (threadId) {
        operationService.markThreadAsUnread(threadId);
    }
    onOpenSettingsRequested: {
        if (openSettingsCallback)
            openSettingsCallback();
    }
    onParticipationFilterChangedByUser: function (value) {
        preferencesService.setParticipationFilter(value);
    }
    onPersistExpandedDateGroups: function (state) {
        if (persistExpandedDateGroupsCallback)
            persistExpandedDateGroupsCallback(state);
    }
    onPersistExpandedRepos: function (state) {
        if (persistExpandedReposCallback)
            persistExpandedReposCallback(state);
    }
    onPopoutVisibilityChanged: function (visible) {
        if (visibilityChangedCallback)
            visibilityChangedCallback(visible);
    }
    onReadFilterChangedByUser: function (value) {
        preferencesService.setReadFilter(value);
    }
    onRefreshNow: {
        if (refreshCallback)
            refreshCallback();
    }
    onRequestThreadAuthors: function (threadId, subjectApiUrl, subjectType) {
        if (authorRequestCallback)
            authorRequestCallback(threadId, subjectApiUrl, subjectType);
    }
}
