# Contributing to Cubelyze

Contributions are welcome through focused issues and pull requests.

## Development setup

Cubelyze requires macOS 14 or later and either Xcode or the standalone Xcode
Command Line Tools. There are no third-party dependencies.

```sh
git clone https://github.com/teddio496/Cubelyze.git
cd Cubelyze
sh scripts/build.sh
open build/Cubelyze.app
```

For interactive development, open `Cubelyze.xcodeproj` in Xcode and run the
Cubelyze scheme on My Mac.

## Pull requests

- Keep changes focused and explain the user-facing reason for them.
- Build with `sh scripts/build.sh` before submitting.
- Manually exercise affected video-review workflows; there is not yet an
  automated test suite.
- Update the README when controls, requirements, storage, or limitations change.
- Do not commit videos, personal analysis data, build products, or signing keys.

By contributing, you agree that your contribution is licensed under the MIT
License included in this repository.

## Maintainer releases

The primary artifact is an ad-hoc signed DMG with an Applications shortcut. A ZIP is also published for users who prefer it. Both are free to produce and host on GitHub Releases, but macOS will show a Gatekeeper warning because they are not Apple notarized. A PKG adds an installer and uninstall burden without benefit for this self-contained app. Developer ID signing and notarization can be added later if a paid Apple Developer Program membership or eligible fee waiver becomes available.

No Apple account or GitHub Actions secrets are required for this release workflow.

Run the **Release** workflow manually with a test version to check packaging without publishing a GitHub Release. Inspect the uploaded artifact and install its DMG on a separate Mac if possible. To publish, push a unique `vMAJOR.MINOR.PATCH` tag (for example `v0.1.0`). The workflow derives `MARKETING_VERSION` and artifact names from the tag, and uses the GitHub run number for `CURRENT_PROJECT_VERSION`. Do not reuse or move a published tag. Confirm the GitHub Release assets and install the DMG after the run. Packaging requires Xcode on a macOS GitHub runner; it cannot be fully verified with Command Line Tools alone.
