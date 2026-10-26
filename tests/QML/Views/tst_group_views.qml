// tst_group_views.qml - verifies group delegate sizing survives resize and model teardown.

import QtQuick
import QtTest

TestCase {
    id: testCase

    function test_groupLifecycle(data) {
        let component = Qt.createComponent("../../../src/QML/Views/" + data.type + ".qml");
        compare(component.status, Component.Ready, component.errorString());
        let group = createTemporaryObject(component, testCase, {
            width: 480,
            expanded: true,
            showAuthorInfo: false
        });
        verify(group);
        group.groupData = {
            label: "Today",
            repository: "owner/repo",
            items: [
                {
                    threadId: "one",
                    title: "Message",
                    subjectType: "PullRequest",
                    unread: true,
                    repository: "owner/repo"
                }
            ]
        };
        let row = findChild(group, "groupMessageRow");
        verify(row);
        verify(row.width > 0);
        let oldWidth = row.width;
        group.width = 560;
        verify(row.width > oldWidth);
        group.groupData = {
            items: []
        };
        wait(0);
        verify(!findChild(group, "groupMessageRow"));
    }

    // Both grouping modes share the same row lifecycle but have independent containers.
    function test_groupLifecycle_data() {
        return [
            {
                tag: "date",
                type: "DateGroupingGroupView"
            },
            {
                tag: "repository",
                type: "RepoGroupingGroupView"
            }
        ];
    }

    name: "GroupViews"
}
