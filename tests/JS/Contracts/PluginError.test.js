// PluginError.test.js - checks the structured error value contract.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = path.resolve(__dirname, "../../../src/JS/Contracts/PluginError.js");
const { createRegistry, loadModule } = require("../../../audit/QmlJavaScript");
const moduleObject = { exports: loadModule("src/JS/Contracts/PluginError.js", createRegistry()) };

const pluginError = moduleObject.exports.create("Request failed.", "HTTP 503", true);
assert.equal(moduleObject.exports.isPluginError(pluginError), true);
assert.equal(pluginError.userMessage, "Request failed.");
assert.equal(pluginError.details, "HTTP 503");
assert.equal(pluginError.retryable, true);
assert.equal(moduleObject.exports.isPluginError(new Error("legacy")), false);

console.log("Plugin error contract tests passed");
