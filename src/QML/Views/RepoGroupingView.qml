// RepoGroupingView.qml - renders repository-based inbox groups.

pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.Common

Column {
    id: view

    property var authorsByThread: ({})
    property var groupingModel: null
    property var groups: []
    property bool isBusy: false
    property bool showAuthorInfo: true
    property int titleLines: GitHubConstants.defaultTitleLines

    signal closePopout
    signal markRepoDone(var items)
    signal markRepoRead(var items)
    signal markThreadDone(string threadId)
    signal markThreadRead(string threadId)
    signal markThreadReadAfterOpen(string threadId)
    signal markThreadUnread(string threadId)
    signal requestThreadAuthors(string threadId, string subjectApiUrl, string subjectType)

    // Honor an explicit group choice before falling back to the default.
    function isGroupExpanded(groupKey) {
        return groupingModel ? groupingModel.isGroupExpanded(groupKey) : true;
    }
    // Replace expansion state so bindings and persistence observe the user's choice.
    function toggleGroup(groupKey) {
        if (groupingModel)
            groupingModel.toggleGroup(groupKey);
    }

    spacing: Theme.spacingS

    Repeater {
        model: view.groups

        delegate: RepoGroupingGroupView {
            required property var modelData

            authorsByThread: view.authorsByThread
            expanded: view.isGroupExpanded(modelData.repository)
            groupData: modelData
            isBusy: view.isBusy
            showAuthorInfo: view.showAuthorInfo
            titleLines: view.titleLines
            width: view.width

            onClosePopout: view.closePopout()
            onMarkRepoDone: function (items) {
                view.markRepoDone(items);
            }
            onMarkRepoRead: function (items) {
                view.markRepoRead(items);
            }
            onMarkThreadDone: function (threadId) {
                view.markThreadDone(threadId);
            }
            onMarkThreadRead: function (threadId) {
                view.markThreadRead(threadId);
            }
            onMarkThreadReadAfterOpen: function (threadId) {
                view.markThreadReadAfterOpen(threadId);
            }
            onMarkThreadUnread: function (threadId) {
                view.markThreadUnread(threadId);
            }
            onRequestThreadAuthors: function (threadId, subjectApiUrl, subjectType) {
                view.requestThreadAuthors(threadId, subjectApiUrl, subjectType);
            }
            onToggleExpanded: view.toggleGroup(modelData.repository)
        }
    }
}
