// ProviderRegistry.js - creates validated facades for supported integrations.

.pragma library

// Read supported identifiers from the single provider enumeration.
function supportedProviderTypes(providerType) {
    return [providerType.GitHub];
}

// Validate the provider and retain a load error rather than exposing a partial API.
function createProvider(providerId, modules) {
    if (!modules || supportedProviderTypes(modules.providerType).indexOf(providerId) < 0)
        return { api: null, properties: null, error: "Unsupported provider type." };

    var properties = modules.githubProperties.create(modules.providerProperties);
    var propertyErrors = modules.providerProperties.validate(properties);
    if (propertyErrors.length > 0) return { api: null, properties: properties, error: propertyErrors.join(" ") };

    var api = modules.githubApi.create(modules.providerApi, properties, modules.githubHelpers);
    var apiErrors = modules.providerApi.validate(api, properties);
    if (apiErrors.length > 0) return { api: null, properties: properties, error: apiErrors.join(" ") };

    return { api: api, properties: properties, error: "" };
}
