// Load QML JavaScript libraries under Node for development checks and tests, preserving shared module identities.
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const srcRoot = path.resolve(__dirname, "..");

// Reuse imported base-class identities across modules, matching QML library imports.
function createRegistry() {
    return new Map();
}

// `relativePath` is relative to the repository root, e.g. "src/JS/Contracts/Resolution.js".
function loadModule(relativePath, registry, globals = {}) {
    const filePath = path.resolve(srcRoot, relativePath);
    if (registry.has(filePath)) return registry.get(filePath);
    const context = {
        console,
        Object,
        JSON,
        Math,
        Date,
        Array,
        Number,
        String,
        Error,
        parseInt,
        parseFloat,
        isNaN,
        isFinite,
        encodeURIComponent,
        ...globals
    };
    vm.createContext(context);
    // Classic workers include the same stateless libraries in their own global context.
    context.Qt = {
        include(importPath) {
            const dependency = path.relative(srcRoot, path.resolve(path.dirname(filePath), importPath));
            const imported = loadModule(dependency, registry, globals);
            for (const [name, value] of Object.entries(imported))
                if (typeof value === "function") context[name] = value;
            return { status: 0 };
        }
    };
    registry.set(filePath, context);
    function importNamespace(importPath, alias) {
        const dependency = path.relative(srcRoot, path.resolve(path.dirname(filePath), importPath));
        context[alias] = loadModule(dependency, registry, globals);
        return "";
    }
    const source = fs
        .readFileSync(filePath, "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/gm, "")
        .replace(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm, (_fullMatch, importPath, alias) => {
            return importNamespace(importPath, alias);
        })
        .replace(/^import \* as (\w+) from "([^"]+)";?\s*$/gm, (_match, alias, importPath) =>
            importNamespace(importPath, alias)
        )
        .replace(/^export (?=(?:function|class|const|let|var)\b)/gm, "");
    vm.runInContext(source, context, { filename: relativePath });
    return context;
}

module.exports = { createRegistry, loadModule };
