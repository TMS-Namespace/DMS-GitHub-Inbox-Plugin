// CacheCommands.test.js - verifies cache paths stay separate from shell source.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = path.resolve(__dirname, "../../../src/JS/Helpers/CacheCommands.js");
const source =
    fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma\s+library\s*$/m, "") +
    "\nmodule.exports = { buildAvatarValidationCommand, buildCacheResetCommand, buildCacheRootResolveCommand };";
const moduleObject = { exports: {} };
vm.runInNewContext(source, { module: moduleObject, Array });

const cacheCommands = moduleObject.exports;
const unsafeLookingPath = "/tmp/cache with 'quotes'; touch /tmp/unexpected.png";
const avatarCommand = Array.from(cacheCommands.buildAvatarValidationCommand([unsafeLookingPath]));
const resetCommand = Array.from(
    cacheCommands.buildCacheResetCommand(
        unsafeLookingPath,
        unsafeLookingPath + "/objects",
        unsafeLookingPath + "/avatars"
    )
);
const resolveCommand = Array.from(cacheCommands.buildCacheRootResolveCommand("plugin; touch /tmp/unexpected"));

assert.equal(avatarCommand[2].includes(unsafeLookingPath), false);
assert.deepEqual(avatarCommand.slice(4), [unsafeLookingPath]);
assert.equal(resetCommand[2].includes(unsafeLookingPath), false);
assert.deepEqual(resetCommand.slice(4), [
    unsafeLookingPath,
    unsafeLookingPath + "/objects",
    unsafeLookingPath + "/avatars"
]);
assert.equal(resolveCommand[2].includes("touch"), false);
assert.equal(resolveCommand[4], "plugin; touch /tmp/unexpected");

console.log("Cache command argument tests passed");
