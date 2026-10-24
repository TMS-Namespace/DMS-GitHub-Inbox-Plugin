// CheckHostContracts.js - compares the host properties exercised by test doubles with installed DMS declarations.

"use strict";

// Aliases keep their native type; ordinary properties carry a readable type and required flag.
function properties(source) {
    const visible = topLevelSource(source);
    return new Map(
        [...visible.matchAll(/\b(required\s+)?property\s+(\w+)\s+(\w+)/g)].map((match) => [
            match[3],
            { type: match[2], required: !!match[1] }
        ])
    );
}

// Keep only the root component's API; nested delegates have their own unrelated required inputs.
function topLevelSource(source) {
    let depth = 0;
    let quote = "";
    let comment = "";
    let visible = "";
    for (let index = 0; index < source.length; index++) {
        const character = source[index];
        const next = source[index + 1];
        if (comment === "line") {
            if (character === "\n") comment = "";
        } else if (comment === "block") {
            if (character === "*" && next === "/") {
                index++;
                comment = "";
            }
        } else if (quote) {
            if (character === "\\") index++;
            else if (character === quote) quote = "";
        } else if (character === "/" && next === "/") {
            comment = "line";
            index++;
        } else if (character === "/" && next === "*") {
            comment = "block";
            index++;
        } else if (["'", '"', "`"].includes(character)) {
            quote = character;
        } else if (character === "{") {
            depth++;
        } else if (character === "}") {
            depth--;
        } else if (depth <= 1) {
            visible += character;
        }
        if (character === "\n") visible += "\n";
    }
    return visible;
}

// Test doubles may omit unused controls but must retain the required inputs and types they expose.
function contractErrors(actualSource, doubleSource) {
    const actual = properties(actualSource);
    const double = properties(doubleSource);
    const errors = [];
    for (const [name, property] of actual)
        if (property.required && !double.get(name)?.required)
            errors.push(`Required host property ${name} is missing or optional in the double.`);
    for (const [name, property] of double) {
        const host = actual.get(name);
        if (!host) {
            errors.push(`Property ${name} is not declared by the installed host.`);
        } else if (
            ![host.type, property.type].some((type) => type === "alias" || type === "var") &&
            host.type !== property.type
        ) {
            errors.push(`Property ${name} differs: host ${host.type}, double ${property.type}.`);
        }
    }
    const methods = (source) =>
        new Map(
            [...topLevelSource(source).matchAll(/\bfunction\s+(\w+)\s*\(([^)]*)\)/g)].map((match) => [
                match[1],
                match[2].trim() ? match[2].split(",").length : 0
            ])
        );
    const actualMethods = methods(actualSource);
    for (const [name, argumentCount] of methods(doubleSource)) {
        if (name.startsWith("_")) continue;
        if (!actualMethods.has(name) || actualMethods.get(name) !== argumentCount)
            errors.push(`Method ${name} does not match the installed host signature.`);
    }
    return errors;
}

module.exports = { contractErrors };
