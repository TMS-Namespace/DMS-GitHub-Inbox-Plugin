// CacheCommands.js - builds safe shell argument arrays for cache operations.

.pragma library

var _AVATAR_VALIDATION_SCRIPT =
    'for avatar_path in "$@"; do\n' +
    "  avatar_login=${avatar_path##*/}\n" +
    "  avatar_login=${avatar_login%.png}\n" +
    '  if [ ! -f "$avatar_path" ]; then\n' +
    '    printf "%s\\n" "$avatar_login"\n' +
    "  else\n" +
    '    avatar_mime=$(file -b --mime-type -- "$avatar_path" 2>/dev/null) || avatar_mime=""\n' +
    '    case "$avatar_mime" in\n' +
    "      image/*) ;;\n" +
    '      *) rm -f -- "$avatar_path"; printf "%s\\n" "$avatar_login" ;;\n' +
    "    esac\n" +
    "  fi\n" +
    "done\n";

var _CACHE_RESET_SCRIPT = 'find "$1" -mindepth 1 -exec rm -rf -- {} + && mkdir -p -- "$2" "$3"';

var _CACHE_ROOT_RESOLVE_SCRIPT = 'printf "%s\\n" "${XDG_CACHE_HOME:-$HOME/.cache}/$1"';

// Build a provider-specific destination from validated subject data.
function buildAvatarValidationCommand(avatarPaths) {
    return ["bash", "-c", _AVATAR_VALIDATION_SCRIPT, "github-avatar-validation"].concat(avatarPaths || []);
}

// Build a provider-specific destination from validated subject data.
function buildCacheResetCommand(cacheDirectory, objectsDirectory, avatarsDirectory) {
    return [
        "bash",
        "-c",
        _CACHE_RESET_SCRIPT,
        "github-cache-reset",
        cacheDirectory,
        objectsDirectory,
        avatarsDirectory
    ];
}

// Build a provider-specific destination from validated subject data.
function buildCacheRootResolveCommand(cacheRootName) {
    return ["bash", "-c", _CACHE_ROOT_RESOLVE_SCRIPT, "github-cache-root", cacheRootName];
}
