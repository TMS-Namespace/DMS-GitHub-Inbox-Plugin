// RunnerWarnings.test.js - verifies warning checks report failures without crashing Qt.

"use strict";

const assert = require("node:assert/strict");
const { unexpectedWarnings, nativeWarnings } = require("../audit/QmlWarnings");
assert.deepEqual(unexpectedWarnings("PASS : test"), []);
assert.deepEqual(unexpectedWarnings("QWARN : test qml: [GitHubInbox] cache: loaded"), []);
assert.equal(unexpectedWarnings("QWARN : test file:///Widget.qml: Unable to assign undefined").length, 1);
assert.equal(unexpectedWarnings("QWARN : test qml: ReferenceError: missingName is not defined").length, 1);
assert.equal(unexpectedWarnings("QCRITICAL: test file:///Widget.qml: broken component").length, 1);
console.log("QML warning classification tests passed");
assert.deepEqual(nativeWarnings("  WARN scene: binding failed\n  WARN qml: [GitHubInbox] queued"), [
    "scene: binding failed"
]);
