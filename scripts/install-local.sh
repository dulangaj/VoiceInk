#!/usr/bin/env bash
#
# Builds VoiceInk, ad-hoc signs it, and installs it to /Applications,
# replacing whatever is already there.
#
# Usage: scripts/install-local.sh [--no-launch]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/.local-build"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/VoiceInk.app"
INSTALLED_APP="/Applications/VoiceInk.app"
BACKUP_APP="/tmp/VoiceInk-previous.app"
LAUNCH=1

for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

cd "$REPO_ROOT"

# A stable signing identity is what keeps macOS from treating each rebuild as a brand
# new app: ad-hoc signing ("-") has no identity, so TCC permissions and Keychain ACLs
# are reset on every install. Prefer Developer ID, then Apple Development, then ad-hoc.
select_identity() {
    if [ -n "${VOICEINK_CODESIGN_IDENTITY:-}" ]; then
        printf '%s' "$VOICEINK_CODESIGN_IDENTITY"
        return
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    local hash
    for prefix in "Developer ID Application:" "Apple Development:"; do
        hash="$(printf '%s\n' "$identities" | awk -v p="$prefix" 'index($0, p) { print $2; exit }')"
        if [ -n "$hash" ]; then
            printf '%s' "$hash"
            return
        fi
    done

    printf '%s' "-"
}

SIGNING_IDENTITY="$(select_identity)"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    SIGNING_REQUIRED=NO
    echo "==> No signing identity found; using ad-hoc (permissions reset on each install)"
else
    SIGNING_REQUIRED=YES
    echo "==> Signing with: $(security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" | sed 's/^ *[0-9]*) *//')"
fi

echo "==> Building (Debug)"
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -xcconfig LocalBuild.xcconfig \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_REQUIRED="$SIGNING_REQUIRED" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_ENTITLEMENTS="$REPO_ROOT/VoiceInk/VoiceInk.local.entitlements" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
    build

[ -d "$BUILT_APP" ] || { echo "Build produced no app at $BUILT_APP" >&2; exit 1; }

# Incremental builds skip Xcode's signing phase, so the bundle can keep an older
# signature. Re-sign explicitly, inside out, so the identity is always the current one.
if [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "==> Re-signing bundle"
    while IFS= read -r nested; do
        codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$nested"
    done < <(find "$BUILT_APP/Contents" \
        \( -name "*.framework" -o -name "*.xpc" -o -name "*.appex" -o -name "*.dylib" \) \
        -mindepth 1 -maxdepth 2 | sort -r)

    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
        --entitlements "$REPO_ROOT/VoiceInk/VoiceInk.local.entitlements" "$BUILT_APP"
    codesign --verify --deep --strict "$BUILT_APP"
fi

echo "==> Quitting any running VoiceInk"
osascript -e 'quit app "VoiceInk"' 2>/dev/null || true
for _ in $(seq 10); do
    pgrep -x VoiceInk >/dev/null || break
    sleep 0.5
done
pkill -x VoiceInk 2>/dev/null || true

if [ -d "$INSTALLED_APP" ]; then
    echo "==> Backing up current install to $BACKUP_APP"
    rm -rf "$BACKUP_APP"
    ditto "$INSTALLED_APP" "$BACKUP_APP"
fi

echo "==> Installing to $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"

echo "==> Installed $(defaults read "$INSTALLED_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"

if [ "$LAUNCH" -eq 1 ]; then
    echo "==> Launching"
    open "$INSTALLED_APP"
fi

echo
if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Ad-hoc signed: macOS will ask for Accessibility, Microphone and Keychain"
    echo "access again after every install."
else
    echo "Signed with a stable identity, so permissions and Keychain access persist"
    echo "across rebuilds. The first install after switching identities still prompts once."
fi
echo "Previous install kept at $BACKUP_APP"
