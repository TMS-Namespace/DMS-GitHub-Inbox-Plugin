// CommentAudit.test.js - guards against the template comments removed during the source audit.

"use strict";

const assert = require("node:assert/strict");
const { checkArchitecture, commentErrors } = require("../audit/CheckArchitecture");

const template = "Build a provider-specific destination from validated subject data.";
for (const prefix of ["// ", "    // ", "/// ", " * ", "/* "])
    assert.equal(commentErrors(prefix + template).length, 1, prefix);
assert.equal(commentErrors("/* " + template + " */").length, 1);
assert.equal(
    commentErrors("// Decode only recognized response fields while preserving notification context.").length,
    1
);
assert.equal(commentErrors("// Keep optimistic mutation state separate from confirmed server state.").length, 1);
assert.match(commentErrors("// Header\r\n// " + template)[0], /line 2:/);
assert.deepEqual(commentErrors("const fixture = " + JSON.stringify("// " + template) + ";"), []);
const accurateComment = "// Remove a failed download only when its path lies under the avatar cache directory.";
assert.deepEqual(commentErrors(accurateComment + "\n" + accurateComment), []);
assert.doesNotThrow(checkArchitecture);

console.log("Comment audit checks passed");
