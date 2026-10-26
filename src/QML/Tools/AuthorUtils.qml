// AuthorUtils.qml - compatibility adapter to the validated GitHub author facade.
// Participant parsing and endpoint rules live in the integration JavaScript module.

pragma Singleton

import QtQuick
import ".."

QtObject {
    readonly property var _helpers: GitHubManager.getProviderApi(GitHubManager.providerTypes[0]).createAuthorTools(GitHubConstants.authorFetchPerPageQuery)

    // Convert recognized GitHub subject links into validated API endpoints.
    function apiUrlFromWebUrl(webUrl) {
        return _helpers.apiUrlFromWebUrl(webUrl);
    }

    // Read the app slug only from the declared GitHub app URL prefix.
    function appSlugFromHtmlUrl(htmlUrl) {
        return _helpers.appSlugFromHtmlUrl(htmlUrl);
    }

    // Append query options without dropping an endpoint's existing query string.
    function appendAuthorQuery(url, query) {
        return _helpers.appendAuthorQuery(url, query);
    }

    // Choose a validated avatar URL, falling back to the app or account endpoint.
    function authorAvatarUrl(authorLike) {
        return _helpers.authorAvatarUrl(authorLike);
    }

    // Deduplicate accounts by login, falling back to their profile or avatar URL.
    function authorKey(login, htmlUrl, avatarUrl) {
        return _helpers.authorKey(login, htmlUrl, avatarUrl);
    }

    // Plan subject and optional timeline endpoints without duplicate requests.
    function buildAuthorFetchUrls(subjectApiUrl, subjectType, includeDetails, reason) {
        return _helpers.buildAuthorFetchUrls(subjectApiUrl, subjectType, includeDetails, reason);
    }

    // Build the repository workflow endpoint only for recognized CI subject types.
    function buildCiApiUrl(repoFullName, subjectType) {
        return _helpers.buildCiApiUrl(repoFullName, subjectType);
    }

    // Collect distinct issue and pull-request roots from recognized response fields.
    function collectSubjectExpansionUrls(value, target, seen) {
        return _helpers.collectSubjectExpansionUrls(value, target, seen);
    }

    // Delegate account avatar URL validation to the provider facade.
    function defaultAvatarUrlForLogin(login) {
        return _helpers.defaultAvatarUrlForLogin(login);
    }

    // Recognize app profiles using the declared GitHub URL prefix.
    function isGitHubAppUrl(htmlUrl) {
        return _helpers.isGitHubAppUrl(htmlUrl);
    }

    // Reject unsupported account names before constructing account URLs.
    function isLikelyGitHubLogin(login) {
        return _helpers.isLikelyGitHubLogin(login);
    }

    // Accept account-like actors while excluding repository organizations.
    function isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl) {
        return _helpers.isLikelyGitHubUserObject(userLike, login, avatarUrl, htmlUrl);
    }

    // Recognize the worker's author envelope before traversing raw API data.
    function isPreExtractedAuthorPayload(value) {
        return _helpers.isPreExtractedAuthorPayload(value);
    }

    // Recognize validated issue and pull-request root endpoints.
    function isThreadParentApiUrl(url) {
        return _helpers.isThreadParentApiUrl(url);
    }

    // Merge existing and incoming participants in order, keeping each account once.
    function mergeAuthorLists(existingAuthors, incomingAuthors) {
        return _helpers.mergeAuthorLists(existingAuthors, incomingAuthors);
    }

    // Strip request options and reject endpoints outside the provider allowlist.
    function normalizeApiUrl(url) {
        return _helpers.normalizeApiUrl(url);
    }

    // Extract recognized actor fields without including repository owners.
    function parseSubjectAuthors(payloadText) {
        return _helpers.parseSubjectAuthors(payloadText);
    }

    // Merge authors from successful response sections, skipping optional failures.
    function parseSubjectAuthorsMulti(payloadText, splitToken) {
        return _helpers.parseSubjectAuthorsMulti(payloadText, splitToken);
    }

    // Read distinct subject roots from valid optional response sections.
    function parseSubjectExpansionUrls(payloadText, splitToken) {
        return _helpers.parseSubjectExpansionUrls(payloadText, splitToken);
    }

    // Normalize a participant and enrich an existing record rather than duplicating it.
    function pushAuthorCandidate(target, byKey, userLike) {
        return _helpers.pushAuthorCandidate(target, byKey, userLike);
    }

    // Derive the repository workflow endpoint from a validated check-suite subject.
    function repoActionsRunsUrlFromSubjectApiUrl(subjectApiUrl) {
        return _helpers.repoActionsRunsUrlFromSubjectApiUrl(subjectApiUrl);
    }

    // Prefer a validated subject endpoint, then its web link, then a CI fallback.
    function resolveSubjectApiUrlForAuthors(item) {
        return _helpers.resolveSubjectApiUrlForAuthors(item);
    }
}
