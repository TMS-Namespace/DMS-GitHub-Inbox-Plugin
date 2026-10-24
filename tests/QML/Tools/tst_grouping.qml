// tst_grouping.qml - tests real QML grouping and filter behavior.

import QtQuick
import QtTest
import "../../../src/QML/Tools"

TestCase {
    function init() {
        repositoryModel.messages = [];
        repositoryModel.groupItemLimit = 25;
        repositoryModel.readFilter = "both";
        repositoryModel.participationFilter = "both";
        dateModel.messages = [];
        dateModel.readFilter = "both";
        dateModel.participationFilter = "both";
    }
    function test_dateBucketsUseUtcCalendarBoundaries() {
        let referenceMs = Date.UTC(2026, 9, 22, 12);
        function bucket(isoTimestamp) {
            return dateModel._dateBucketValue({
                updatedAtMs: Date.parse(isoTimestamp)
            }, referenceMs);
        }

        compare(bucket("2026-10-22T00:00:00Z"), "today");
        compare(bucket("2026-10-21T23:59:00Z"), "yesterday");
        compare(bucket("2026-10-20T23:59:00Z"), "two_days_ago");
        compare(bucket("2026-10-19T00:00:00Z"), "this_week");
        compare(bucket("2026-10-12T00:00:00Z"), "previous_week");
        compare(bucket("2026-10-05T00:00:00Z"), "two_weeks_ago");
        compare(bucket("2026-09-30T23:59:00Z"), "previous_month");
        compare(bucket("2026-01-01T00:00:00Z"), "this_year");
        compare(bucket("2025-12-31T23:59:00Z"), "previous_year");
        compare(bucket("2024-12-31T23:59:00Z"), "older");
    }
    function test_dateGroupingRetainsDateBucketsAndSortOrder() {
        let now = Date.now();
        dateModel.messages = [
            {
                threadId: "older",
                updatedAtMs: now - 86400000 * 900,
                unread: true,
                participated: false
            },
            {
                threadId: "newer",
                updatedAtMs: now - 1000,
                unread: true,
                participated: false
            }
        ];

        compare(dateModel.filteredMessages[0].threadId, "newer");
        compare(dateModel.groups.length, 2);
        verify(dateModel.groups.some(group => group.key === "today" && group.items.length === 1));
        verify(dateModel.groups.some(group => group.key === "older" && group.items.length === 1));
    }
    function test_fiveHundredDaysAgoDependsOnUtcCalendarYear() {
        let in2026 = Date.UTC(2026, 9, 22, 12);
        let notificationAt = in2026 - 500 * 24 * 60 * 60 * 1000;
        compare(dateModel._dateBucketValue({
            updatedAtMs: notificationAt
        }, in2026), "previous_year");

        let in2027 = Date.UTC(2027, 9, 22, 12);
        compare(dateModel._dateBucketValue({
            updatedAtMs: notificationAt
        }, in2027), "older");
    }
    function test_largerCalendarUnitsTakePriorityAtYearBoundary() {
        let justAfterUtcNewYear = Date.UTC(2026, 0, 1, 0, 30);
        compare(dateModel._dateBucketValue({
            updatedAtMs: Date.UTC(2025, 11, 31, 23, 30)
        }, justAfterUtcNewYear), "previous_year");

        let justAfterMonthStart = Date.UTC(2026, 9, 1, 0, 30);
        compare(dateModel._dateBucketValue({
            updatedAtMs: Date.UTC(2026, 8, 30, 23, 30)
        }, justAfterMonthStart), "previous_month");
    }
    function test_repositoryGroupingFiltersAndLimits() {
        repositoryModel.groupItemLimit = 1;
        repositoryModel.messages = [
            {
                threadId: "new",
                repository: "owner/repo",
                updatedAtMs: 3000,
                unread: true,
                participated: true
            },
            {
                threadId: "old",
                repository: "owner/repo",
                updatedAtMs: 2000,
                unread: false,
                participated: false
            },
            {
                threadId: "other",
                repository: "owner/other",
                updatedAtMs: 1000,
                unread: true,
                participated: false
            }
        ];

        compare(repositoryModel.groups.length, 2);
        compare(repositoryModel.groups[0].repository, "owner/repo");
        compare(repositoryModel.groups[0].items.length, 1);
        compare(repositoryModel.groups[0].allItems.length, 2);
        compare(repositoryModel.groups[0].items[0].threadId, "new");

        repositoryModel.participationFilter = "yes";
        compare(repositoryModel.filteredMessages.length, 1);
        compare(repositoryModel.filteredMessages[0].threadId, "new");

        repositoryModel.readFilter = "yes";
        compare(repositoryModel.filteredMessages.length, 0);
    }
    function test_weekThirtyToThirtyTwoUsesMonthBucketFirst() {
        let weekThirtyTwoWednesday = Date.UTC(2026, 7, 5, 12);
        let weekThirtyWednesday = Date.UTC(2026, 6, 22, 12);
        compare(dateModel._dateBucketValue({
            updatedAtMs: weekThirtyWednesday
        }, weekThirtyTwoWednesday), "previous_month");
    }

    name: "GroupingModel"

    RepoGroupingModel {
        id: repositoryModel
    }
    DateGroupingModel {
        id: dateModel
    }
}
