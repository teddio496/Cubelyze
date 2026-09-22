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
