// CheckArchitecture.js - static checks for module boundaries required by the project.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { contractErrors } = require("./CheckHostContracts");

const root = path.resolve(__dirname, "..");

function stripComments(source) {
    return source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^[ \t]*\/\/.*$/gm, "");
}

function checkArchitecture() {
    const failures = [];
    const topLevelEntries = new Set(fs.readdirSync(root));
    for (const directory of ["audit", "images", "support", "src"])
        if (!topLevelEntries.has(directory)) failures.push(`Missing lowercase top-level directory: ${directory}`);
    for (const oldCaseDirectory of ["Images", "Support", "JS", "QML", "js", "qml"])
        if (topLevelEntries.has(oldCaseDirectory))
            failures.push(`Use the lowercase directory name instead of ${oldCaseDirectory}.`);

    const contractDirectories = ["src/QML/Contracts"];
    for (const directory of contractDirectories) {
        for (const filename of fs.readdirSync(path.join(root, directory)).filter((name) => name.endsWith(".qml"))) {
            const source = stripComments(fs.readFileSync(path.join(root, directory, filename), "utf8"));
            if (/\bfunction\s+[A-Za-z_$][\w$]*\s*\(/.test(source))
                failures.push(`${directory}/${filename} contains behavior; contracts must only hold typed data.`);
        }
    }

    const statefulServiceNames = [
        "ApiCallStats.qml",
        "AvatarPreloader.qml",
        "CacheCoordinator.qml",
        "InboxOperations.qml",
        "PluginCache.qml",
        "ResourceRepository.qml",
        "SecretStore.qml"
    ];
    for (const filename of statefulServiceNames) {
        if (fs.existsSync(path.join(root, "src/QML/Tools", filename)))
            failures.push(
                `src/QML/Tools/${filename} owns shared state; stateful components belong in src/QML/Services.`
            );
        if (!fs.existsSync(path.join(root, "src/QML/Services", filename)))
            failures.push(
                `src/QML/Services/${filename} is missing; this stateful component belongs in src/QML/Services.`
            );
    }

    const qmlRoot = path.join(root, "src/QML");
    const qmlFiles = collectFiles(qmlRoot, ".qml");
    const javascriptFiles = [".js", ".mjs"].flatMap((suffix) => collectFiles(path.join(root, "src/JS"), suffix));
    // Root manifests expose all types, so also check type usage through those broad imports.
    const viewTypes = collectFiles(path.join(qmlRoot, "Views"), ".qml").map((filename) =>
        path.basename(filename, ".qml")
    );
    for (const filename of qmlFiles) {
        const relativePath = path.relative(qmlRoot, filename);
        const source = stripComments(fs.readFileSync(filename, "utf8"));
        if (
            relativePath.startsWith("Views/") &&
            /\b(?:Process|WorkerScript)\s*\{|\.enqueueAuthorFetch\s*\(/.test(source)
        )
            failures.push(`${relativePath} performs background work; views must delegate it to services.`);
        if (/\bimport\s+qs\.Widgets\b|\bDank[A-Z]\w*\s*\{/.test(source))
            failures.push(`${relativePath} must use the current DCommon widget module and D* names.`);
        if (
            relativePath.startsWith("Views/") &&
            /\b(?:Flickable|ListView|GridView|ScrollBar|Button|TextField|Slider|Switch|ComboBox|ToolTip)\s*\{/.test(
                source
            )
        )
            failures.push(`${relativePath} must use shared Dux controls instead of raw Qt controls.`);
        if (/^(?:Contracts|Services|Tools|BackgroundWorkers)\//.test(relativePath)) {
            for (const typeName of viewTypes)
                if (new RegExp(`\\b${typeName}\\s*\\{`).test(source))
                    failures.push(`${relativePath} instantiates view ${typeName}; lower layers cannot own views.`);
            if (/\bimport\s+["'][^"']*Views(?:\/|["'])/.test(source))
                failures.push(`${relativePath} imports the view layer.`);
        }
    }
    // Audit doubles against installed DMS module locations when the host is available.
    const hostRoot = process.env.DMS_SOURCE_ROOT || "/usr/share/quickshell/dms";
    if (fs.existsSync(hostRoot)) {
        const doublesRoot = path.join(root, "tests/HostModules/qs");
        for (const filename of collectFiles(doublesRoot, ".qml")) {
            const relativePath = path.relative(doublesRoot, filename);
            if (!fs.existsSync(path.join(hostRoot, relativePath)))
                failures.push(`Host double ${relativePath} does not exist in the installed DMS module.`);
            else if (!relativePath.startsWith("Common/")) {
                const errors = contractErrors(
                    fs.readFileSync(path.join(hostRoot, relativePath), "utf8") +
                        (relativePath === "DCommon/Widgets/DActionButton.qml"
                            ? "\n" + fs.readFileSync(path.join(hostRoot, "DCommon/Widgets/StyledButton.qml"), "utf8")
                            : ""),
                    fs.readFileSync(filename, "utf8")
                );
                for (const error of errors) failures.push(`${relativePath}: ${error}`);
            }
        }
    }
    for (const filename of javascriptFiles) {
        const source = fs.readFileSync(filename, "utf8");
        if (!source.startsWith("//")) failures.push(`${path.relative(root, filename)} needs a role header.`);
        if (/throw\s+(?:new\s+Error\b|["'])/.test(stripComments(source)))
            failures.push(`${path.relative(root, filename)} must throw PluginError rather than an untyped exception.`);
        const lineCount = fs.readFileSync(filename, "utf8").split(/\r?\n/).length;
        if (lineCount > 900)
            failures.push(
                `${path.relative(root, filename)} is ${lineCount} lines; JavaScript modules must not exceed 900 lines.`
            );
    }
    for (const filename of [...qmlFiles, ...javascriptFiles]) {
        const lines = fs.readFileSync(filename, "utf8").split(/\r?\n/);
        for (let index = 0; index < lines.length; index++)
            if (/^\s*function\s+\w+\s*\(/.test(lines[index]) && !/^\s*(?:\/\/|\*|\/\*)/.test(lines[index - 1] || ""))
                failures.push(`${path.relative(root, filename)}:${index + 1}: document the named function's contract.`);
    }

    const directLogging = qmlFiles.filter((filename) =>
        /\bconsole\.(?:log|info|warn|error|debug)\s*\(/.test(stripComments(fs.readFileSync(filename, "utf8")))
    );
    if (directLogging.length)
        failures.push(
            `QML logging must use PluginLogger: ${directLogging.map((file) => path.relative(root, file)).join(", ")}`
        );

    const directJavaScriptLogging = javascriptFiles.filter((filename) =>
        /\bconsole\.(?:log|info|warn|error|debug)\s*\(/.test(stripComments(fs.readFileSync(filename, "utf8")))
    );
    if (directJavaScriptLogging.length)
        failures.push(
            `JavaScript modules must not log: ${directJavaScriptLogging.map((file) => path.relative(root, file)).join(", ")}`
        );

    const abbreviatedCatchBindings = javascriptFiles.filter((filename) =>
        /\bcatch\s*\(\s*(?:e|err)\s*\)/.test(stripComments(fs.readFileSync(filename, "utf8")))
    );
    if (abbreviatedCatchBindings.length)
        failures.push(
            `Use a descriptive exception binding: ${abbreviatedCatchBindings.map((file) => path.relative(root, file)).join(", ")}`
        );

    const serializationPath = path.join(root, "src/JS/Storage/CacheFormat.js");
    const serialization = fs.readFileSync(serializationPath, "utf8");
    if ((serialization.match(/function normalizeDoneThreadState\s*\(/g) || []).length !== 1)
        failures.push("Cache legacy done-state migration must have one canonical implementation.");
    const operations = fs.readFileSync(path.join(root, "src/QML/Services/InboxOperations.qml"), "utf8");
    if (!/return CacheSerialization\.normalizeDoneThreadState\(source\)/.test(operations))
        failures.push("InboxOperations must use the canonical cache done-state migration helper.");

    const directIntegrationImports = qmlFiles.filter((filename) => {
        const source = stripComments(fs.readFileSync(filename, "utf8"));
        return (
            /\bimport\s+["'][^"']*JS\/Integrations\//.test(source) && !filename.endsWith("/Services/GitHubManager.qml")
        );
    });
    if (directIntegrationImports.length)
        failures.push(
            `Only GitHubManager may import integration internals: ${directIntegrationImports.map((file) => path.relative(root, file)).join(", ")}`
        );

    const requestFiles = qmlFiles.filter((filename) =>
        /\bcurl\s+-|\[\s*["']curl["']\s*,/.test(stripComments(fs.readFileSync(filename, "utf8")))
    );
    for (const filename of requestFiles) {
        const source = stripComments(fs.readFileSync(filename, "utf8"));
        if (!/providerApi\.(?:buildCurlRetryArguments|getRetryPolicy)\s*\(/.test(source))
            failures.push(`${path.relative(root, filename)} must use the provider facade retry policy.`);
    }

    if (failures.length) throw new Error(failures.join("\n"));
    return [
        "contracts contain data only",
        "source layout and view dependencies respect layer boundaries",
        "views delegate background work to services",
        "named function contracts and source headers are documented",
        "host doubles match installed module locations when available",
        "JavaScript module size is bounded",
        "QML logging is centralized",
        "JavaScript modules do not log directly",
        "exception bindings are descriptive",
        "cache migration has one implementation",
        "integration internals are behind GitHubManager",
        "network requests use facade retry policy"
    ];
}

function collectFiles(directory, suffix) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const filename = path.join(directory, entry.name);
        return entry.isDirectory() ? collectFiles(filename, suffix) : entry.name.endsWith(suffix) ? [filename] : [];
    });
}

module.exports = { checkArchitecture };

if (require.main === module) {
    try {
        console.log(`Architecture: ${checkArchitecture().join("; ")}.`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
