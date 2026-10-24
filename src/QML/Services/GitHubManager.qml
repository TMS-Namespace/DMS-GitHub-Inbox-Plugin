// GitHubManager.qml - validates integrations and exposes their API facades.

pragma Singleton

import QtQuick
import "../../JS/Contracts/ProviderApi.js" as ProviderApi
import "../../JS/Contracts/ProviderProperties.js" as ProviderProperties
import "../../JS/Contracts/ProviderType.js" as ProviderType
import "../../JS/Integrations/GitHub/GitHubHelpers.js" as GitHubHelpers
import "../../JS/Integrations/GitHub/GitHubProviderApi.js" as GitHubProviderApi
import "../../JS/Integrations/GitHub/GitHubProviderProperties.js" as GitHubProviderProperties
import "../../JS/Integrations/ProviderRegistry.js" as ProviderRegistry
import ".."

QtObject {
    id: manager

    readonly property var _github: ProviderRegistry.createProvider(ProviderType.GitHub, _modules)
    readonly property var _modules: ({
            providerType: ProviderType,
            providerApi: ProviderApi,
            providerProperties: ProviderProperties,
            githubApi: GitHubProviderApi,
            githubProperties: GitHubProviderProperties,
            githubHelpers: GitHubHelpers
        })
    readonly property var loadErrors: _github.error ? [_github.error] : []
    readonly property var properties: _github.properties || ({})
    readonly property var providerTypes: ProviderRegistry.supportedProviderTypes(ProviderType)

    // Expose only a successfully loaded provider facade; unknown providers have no API.
    function getProviderApi(providerId) {
        if (providerTypes.indexOf(providerId) < 0)
            return null;
        return _github.api;
    }
}
