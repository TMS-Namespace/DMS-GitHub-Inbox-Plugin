// Check that each QML directory declares its local types and the root module exports all source types.

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const repositoryRoot = path.resolve(__dirname, "..");
const qmlRoot = path.join(repositoryRoot, "src/QML");

function collectQmlFiles(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const entryPath = path.join(directory, entry.name);
        return entry.isDirectory() ? collectQmlFiles(entryPath) : entry.name.endsWith(".qml") ? [entryPath] : [];
    });
}

function manifestFiles(directory) {
    const manifestPath = path.join(directory, "qmldir");
    if (!fs.existsSync(manifestPath)) throw new Error(`Missing qmldir: ${path.relative(repositoryRoot, directory)}`);

    return fs
        .readFileSync(manifestPath, "utf8")
        .split(/\r?\n/)
        .map((line) => line.trim().split(/\s+/))
        .filter((parts) => parts.length >= 3 && !parts[0].startsWith("#"))
        .map((parts) => path.resolve(directory, parts[parts.length - 1]));
}

function assertSameFiles(actual, expected, label) {
    const actualSet = new Set(actual);
    const expectedSet = new Set(expected);
    const missing = [...expectedSet].filter((file) => !actualSet.has(file));
    const extra = [...actualSet].filter((file) => !expectedSet.has(file));
    if (missing.length || extra.length) {
        const details = [
            ...missing.map((file) => `missing ${path.relative(repositoryRoot, file)}`),
            ...extra.map((file) => `unexpected ${path.relative(repositoryRoot, file)}`)
        ];
        throw new Error(`${label}: ${details.join(", ")}`);
    }
}

function checkQmldir() {
    const sourceFiles = collectQmlFiles(qmlRoot);
    for (const directory of [qmlRoot, ...new Set(sourceFiles.map((file) => path.dirname(file)))]) {
        const listedFiles = manifestFiles(directory);
        const localFiles = sourceFiles.filter((file) => path.dirname(file) === directory);
        if (directory === qmlRoot) assertSameFiles(listedFiles, sourceFiles, "QML root module manifest");
        else assertSameFiles(listedFiles, localFiles, `${path.relative(repositoryRoot, directory)} manifest`);
    }
    return sourceFiles.length;
}

if (require.main === module) {
    try {
        console.log(`QML manifests: ${checkQmldir()} source types match their qmldir declarations.`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}

module.exports = { checkQmldir };
