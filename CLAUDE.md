# CLAUDE.md

## Building

Build only with the project script — never call `xcodebuild ... build` directly:

```bash
scripts/install-local.sh   # --no-launch to skip relaunching the app
```

It builds Debug into `.local-build`, signs with a stable identity so permissions
survive rebuilds, and installs to `/Applications`.

## Tests

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
    -derivedDataPath .local-build -xcconfig LocalBuild.xcconfig \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements"
```

The test host needs those signing flags; without them the build fails asking for a
provisioning profile.
