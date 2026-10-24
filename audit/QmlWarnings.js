// QmlWarnings.js - identifies runtime warnings without making Qt abort and dump core.

"use strict";

// Deliberate plugin diagnostics use qml.warn too; actual Qt runtime warnings still fail verification.
function unexpectedWarnings(output) {
    return String(output || "")
        .split(/\r?\n/)
        .filter((line) => /^Q(?:WARN|CRITICAL)\s*:/.test(line) && !/\bqml: \[GitHubInbox\] /.test(line));
}

// Native qs logs have a different prefix from QtTest output; retain the actual diagnostic text.
function nativeWarnings(output) {
    return String(output || "")
        .split(/\r?\n/)
        .filter((line) => /\bWARN\b/.test(line) && !line.includes("[GitHubInbox]"))
        .map((line) => line.trim().replace(/^WARN\s+/, ""));
}

module.exports = { unexpectedWarnings, nativeWarnings };
