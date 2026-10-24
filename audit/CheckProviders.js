// CheckProviders.js - validates the registered provider factories without starting QML.

"use strict";

const { createRegistry, loadModule } = require("./QmlJavaScript");

// Load one copy of each QML JavaScript library and its declared dependencies.
function checkProviders() {
    const registry = createRegistry();
    const providerType = loadModule("src/JS/Contracts/ProviderType.js", registry);
    const providerApi = loadModule("src/JS/Contracts/ProviderApi.js", registry);
    const providerProperties = loadModule("src/JS/Contracts/ProviderProperties.js", registry);
    const githubApi = loadModule("src/JS/Integrations/GitHub/GitHubProviderApi.js", registry);
    const githubProperties = loadModule("src/JS/Integrations/GitHub/GitHubProviderProperties.js", registry);
    const githubHelpers = loadModule("src/JS/Integrations/GitHub/GitHubHelpers.js", registry);
    const providerRegistry = loadModule("src/JS/Integrations/ProviderRegistry.js", registry);
    const modules = {
        providerType,
        providerApi,
        providerProperties,
        githubApi,
        githubProperties,
        githubHelpers
    };
    const providerTypes = providerRegistry.supportedProviderTypes(providerType);
    for (const providerTypeName of providerTypes) {
        const provider = providerRegistry.createProvider(providerTypeName, modules);
        const errors = providerApi
            .validate(provider.api, provider.properties)
            .concat(providerProperties.validate(provider.properties));
        if (provider.error || errors.length > 0) {
            const details = provider.error || errors.join(" ");
            throw {
                name: "PluginError",
                userMessage: `Provider ${providerTypeName} failed validation.`,
                details,
                retryable: false
            };
        }
    }
    return Array.from(providerTypes);
}

module.exports = { checkProviders };

if (require.main === module) {
    try {
        process.stdout.write(`Provider contracts: ${checkProviders().join(", ")}; all implementations conform.\n`);
    } catch (error) {
        process.stderr.write(`${error.userMessage || "Provider validation failed."} ${error.details || ""}\n`);
        process.exitCode = 1;
    }
}
