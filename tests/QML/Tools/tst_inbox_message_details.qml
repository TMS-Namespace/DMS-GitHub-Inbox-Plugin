// tst_inbox_message_details.qml - tests resolved notification subject details.

import QtQuick
import QtTest
import "../../../src/QML/Tools"

TestCase {
    function test_noopReturnsOriginalArray() {
        let messages = [
            {
                threadId: "thread-1",
                webUrl: "https://github.com/org/repo/pull/42",
                webUrlResolved: true,
                subjectReference: "42"
            }
        ];

        let result = InboxMessageDetails.withResolvedSubjectDetails(messages, "thread-1", "https://github.com/org/repo/pull/42", "#42");

        compare(result, messages);
    }
    function test_resolvesUrlAndNormalizesSubjectReferenceForMatchingThread() {
        let original = {
            threadId: "thread-1",
            webUrl: "",
            webUrlResolved: false,
            subjectReference: ""
        };
        let other = {
            threadId: "thread-2",
            title: "Untouched"
        };
        let messages = [original, other];
        let result = InboxMessageDetails.withResolvedSubjectDetails(messages, "thread-1", "https://github.com/org/repo/pull/42", "#42");

        verify(result !== messages);
        verify(result[0] !== original);
        compare(result[0].webUrl, "https://github.com/org/repo/pull/42");
        compare(result[0].webUrlResolved, true);
        compare(result[0].subjectReference, "42");
        compare(result[1], other);
        compare(original.subjectReference, "");
    }

    name: "InboxMessageDetails"
}
