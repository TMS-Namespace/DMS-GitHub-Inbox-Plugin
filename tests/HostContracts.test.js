// HostContracts.test.js - verifies that host-contract audits catch overly permissive doubles.

"use strict";
const assert = require("node:assert/strict");
const { contractErrors } = require("../audit/CheckHostContracts");
assert.deepEqual(contractErrors("required property string settingKey", "required property string settingKey"), []);
assert.equal(contractErrors("required property string settingKey", "property string settingKey").length, 1);
assert.equal(contractErrors("property string value", "property bool value").length, 1);
assert.equal(contractErrors("property string value", "property int madeUpProperty").length, 1);
assert.deepEqual(contractErrors("property alias text: input.text", "property string text"), []);
console.log("Host contract audits passed");
assert.equal(contractErrors("Item {function saveValue(key, value) {}}", "Item {function saveValue(key) {}}").length, 1);
assert.deepEqual(
    contractErrors(
        "Item {property string value; Item {required property var modelData}}",
        "Item {property string value}"
    ),
    []
);
