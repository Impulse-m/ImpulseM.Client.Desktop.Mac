# Building ImpulseM for macOS

The app is an Xcode workspace (`Telegram-Mac.xcworkspace`) that links a small set of native
libraries built once from `core-xprojects/` and a collection of local Swift packages
from `packages/` and `submodules/telegram-ios/submodules/`. Most of them resolve from local
paths. Two remote Swift dependencies need network access on the first resolve: the LiveKit
SDK (`client-sdk-swift`, used for calls) and the Centrifugo Swift SDK, which the ImpulseTransport
package reads as a sibling checkout (see the requirements and the CI workflow).

## Requirements

- macOS on Apple Silicon or Intel. On Apple Silicon, Rosetta 2 is needed: the `tde2e`
  build compiles an x86_64 code-generation tool and runs it.
- Full Xcode 26 (CI selects the default Xcode of the `macos-26` image). Command Line Tools alone are
  not enough. Make it the active developer directory:
  ```
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
- Homebrew and these packages:
  ```
  brew install cmake ninja meson nasm yasm zlib autoconf libtool automake pkg-config
  ```
- Git access to `github.com` for the submodules. All `.gitmodules` URLs are HTTPS.

## 1. Clone and check out the submodules

```
git clone https://github.com/Impulse-m/ImpulseM.Client.Desktop.Mac.git
cd ImpulseM.Client.Desktop.Mac
sh scripts/ci-submodules.sh
```

For an existing checkout, run the same script again; it is safe to repeat.

`scripts/ci-submodules.sh` initialises every submodule the app and its native libraries are
built from, from one explicit list. Nothing recurses. Do not replace it with
`git submodule update --init --recursive`: the nested checkouts of the removed native calls
stack are not needed, and the recursive update would fetch them.

The script initialises the nested `submodules/telegram-ios` checkouts that the native
libraries are built from: `third-party/td`, `third-party/dav1d` and
`third-party/wallet-engine`.

## 2. Prepare the machine

```
sh scripts/setup_build_env.sh
```

The script is idempotent and does everything from the requirements list that can be
automated: installs Homebrew and the packages, installs Rosetta 2 on Apple Silicon,
checks that full Xcode is selected, and initialises the submodules through
`scripts/ci-submodules.sh`.

Run it with `--build` to continue straight into step 3.

## 3. Build the native libraries (once)

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
sh scripts/configure_frameworks.sh
```

The native stack is small. Calls run on LiveKit, which comes in as SwiftPM binaries, so
WebRTC, OpenH264 and tgcalls are not built here. The script:

1. Generates TelegramApi's SwiftPM sources with SwiftTL, then the FlatSerialization
   sources for TelegramCore with the bundled `scripts/flatc`.
2. Builds, in order, `OpenSSLEncryption` (a dependency of `tde2e`), `libopus`, `libvpx`,
   `Mozjpeg`, `libwebp`, `dav1d`, `ffmpeg` and `tde2e` through their projects in
   `core-xprojects/<lib>/`. Outputs land in `core-xprojects/<lib>/build`, which is
   git-ignored.
3. Copies public headers into the `SharedHeaders` directories that the OpusBinding,
   FFMpegBinding, OpenSSLEncryptionProvider, libwebp and Mozjpeg packages expect.
4. Runs the `td` macOS cleanup for `TdBinding`.

Framework preparation compares source, toolchain and dependency fingerprints and
checks required libraries and headers before reusing a build.
Valid cache hits skip the framework's Xcode invocation. Missing or inconsistent
outputs are repaired, and a success stamp is written only after output checks pass.
Build directories without a stamp are rebuilt rather than assumed to be complete.
To rebuild everything from scratch, put `yes` into `scripts/rebuild` (it is `no` by
default), run the script, and set it back to `no`.

`CMAKE_POLICY_VERSION_MINIMUM=3.5` is still required with CMake 4, which dropped support for
the old `cmake_minimum_required` versions that mozjpeg and td still declare. Keep it while
those cmake-built libraries are part of the build.

## 4. Build the app

Open `Telegram-Mac.xcworkspace` in Xcode, not `Telegram.xcodeproj`. The workspace also
contains the `RLottie_Xcode`, `CodeSyntax` and `Sparkle` projects that the app links,
and a bare `Telegram.xcodeproj` build cannot find them.

Schemes:

| Scheme | Use |
|---|---|
| `ImpulseM` | Day-to-day development, Debug configuration (`Telegram-Mac/Debug.xcconfig`) |
| `TelegramShare` | The share extension on its own |
| `Release` | Release archives (`Telegram-Mac/Release.xcconfig`) |

From the command line:

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme ImpulseM -configuration Debug build
```

The app product is `ImpulseM.app` (executable `ImpulseM`; the Swift module stays `Telegram`).
The share extension product is `ImpulseMShare`. Both targets set `MACOSX_DEPLOYMENT_TARGET`
to 12.0. Local Swift packages resolve from their paths in the workspace; the LiveKit and
Centrifugo SDKs are fetched on the first resolve (see the top of this file).

The GitHub Actions workflow `.github/workflows/macos.yml` builds the app unsigned on
`macos-26` with `CODE_SIGNING_REQUIRED=NO`, runs the package test suites, and uploads the
unsigned app bundle as an artifact.

### Generated TelegramApi sources

`scripts/configure_frameworks.sh` prepares the generated Swift and Objective-C API
sources before Xcode resolves packages. Both CI build paths run this preparation
before building or archiving. The shared `ImpulseM`, `Release`, and `TelegramShare`
schemes also refresh generation before normal builds. Both app targets validate the
generated files, so a failed generator cannot silently build against stale output.

Generation is incremental: the schema, SwiftTL sources, generator script, selected
Swift toolchain, and generated file contents are checked. Unchanged files keep their
timestamps. Generation runs in a temporary directory and publishes only complete
output; concurrent preparation calls are serialized. Outputs and the preparation
stamp remain git-ignored.

For a checkout with existing native libraries but no generated API sources, run this
once **before opening Xcode** or invoking `xcodebuild`:

```
python3 scripts/prepare-telegram-api.py
```

This is already included in the normal framework setup and CI paths. Xcode discovers
package source files before scheme pre-actions, so a pre-action alone cannot bootstrap
missing files on the first build. If a submodule update changes the set of generated
filenames, prepare and reopen the workspace to refresh package discovery. Direct
`swift build`/`swift test` consumers should also run preparation first.

Focused verification without building the main app:

```
python3 tools/tests/telegram-api-generation/test_generation.py
python3 tools/tests/telegram-api-generation/xcode.py
python3 tools/tests/no-paid-messages-token/run.py
```

The Xcode test builds a temporary command-line app against a clean copy of TelegramApi,
then checks incremental generation, schema changes, and failed-generator handling.
It prints the temporary directory containing its build logs.

### Signing

The bundle identifiers are `net.impulsem.messenger.mac` for the app and
`net.impulsem.messenger.mac.share` for the share extension. The app group and the keychain
access group are `<TEAM>.net.impulsem.messenger.mac` (the first keychain group must equal the
app group), shared with the extensions. `<TEAM>` is the Apple Team ID.

The repository does not contain a team. `DEVELOPMENT_TEAM` and the entitlement prefixes are
the placeholder `TEAM_ID_PLACEHOLDER`, so the project does not sign with a real team as
checked in. Without the team, build unsigned, as CI does:

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme ImpulseM -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The CI workflow builds unsigned only. Developer ID signing, notarization and Sparkle update
signing belong to a release job, which runs only when its CI secrets are present. Without the
secrets the job produces an unsigned artifact; it does not fail for lack of them.

The entitlements carry no `webcredentials` associated domain. Add one only together with the
passkey sign-in, which is hidden until passkeys are enabled.

## Build configurations and release channels

`Telegram-Mac/common.xcconfig` holds the shared settings. The channel is selected by an
xcconfig that defines `TYPE` (a Swift compiler flag) plus the Sparkle feed URL:

| xcconfig | `TYPE` | Feed |
|---|---|---|
| `Telegram-Mac/Debug.xcconfig` | `BETA` | beta feed |
| `Telegram-Mac/Release.xcconfig` | `STABLE` | `macos.impulsem.net/updates/versions.xml` |
| `configurations/Stable.xcconfig` | `STABLE` | `macos.impulsem.net/updates/versions.xml` |
| `configurations/Beta.xcconfig` | `BETA` | `macos.impulsem.net/beta/versions.xml` |
| `configurations/Alpha.xcconfig` | `ALPHA` | `macos.impulsem.net/alpha/versions.xml` |
| `configurations/AppStore.xcconfig` | `APP_STORE` | none (Mac App Store build) |

`buildbox/build-mac.sh <Alpha|Beta|Stable|AppStore>` is the release recipe: it copies the
tree to `~/build-<channel>`, runs `scripts/configure_frameworks.sh`, copies the chosen
`configurations/<channel>.xcconfig` over `Telegram-Mac/Release.xcconfig`, and runs

```
xcodebuild archive -workspace Telegram-Mac.xcworkspace -scheme Release -configuration Release \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) <CHANNEL>'
```

where `<CHANNEL>` is `ALPHA`, `BETA`, `STABLE` or `APP_STORE`. `TYPE` from the xcconfig only reaches
the app target; Swift packages under `packages/` do not read it, so the channel condition is passed on
the command line, which applies to every target including packages. Builds started from the Xcode UI
do not get it, so `#if BETA` / `STABLE` / `ALPHA` / `APP_STORE` inside packages are false there.

The script then extracts `ImpulseM.app` and its dSYM from the archive. GitLab runs this direct Mac
build through `buildbox/internal.sh`, which verifies and deploys the result while
holding the existing machine-wide lock. `buildbox/build.sh` is the separate legacy
Parallels VM build path.

### CI build reuse and timing

Source synchronization preserves native outputs, generated TelegramApi and
FlatSerialization sources, the SwiftTL build cache and generated shared headers.
Generators still run their validation; unchanged Swift files and headers keep their
timestamps, and removed generated files are deleted.

GitLab retains `.ci-build-logs/<job-id>/` for seven days, including failed jobs:

- `frameworks.log`: preparation output and framework cache decisions.
- `xcodebuild.log`: full archive output and Xcode's build timing summary.
- `timings.tsv`: wall-clock stage durations and exit codes. The aggregate `build`
  row includes its nested preparation, archive and compression stages.

Archive builds disable compiler indexing. Optimization, both CPU architectures,
channel conditions, signing, dSYMs and deployment serialization are preserved.
No explicit DerivedData cleanup is added; Xcode continues to use its normal location.

On a runner with compilation-cache support, set the CI variable
`TELEGRAM_COMPILATION_CACHE=YES` to trial Xcode compilation caching with diagnostic
remarks. `NO` explicitly disables it; leaving it unset preserves the toolchain's
default. Compare a baseline, a repeated build and a small source change before
enabling it permanently. The normal pipeline does not opt into this setting.

`TELEGRAM_BUILD_ROOT` optionally relocates the `build-<channel>` directories; its
default is the user's home directory. This is also used by isolated script tests.
It does not relax the machine-wide build lock.

Run the focused checks without deploying:

```
python3 tools/tests/ci-build/test_incremental.py
python3 tools/tests/telegram-api-generation/test_generation.py
python3 tools/tests/ci-build/xcode.py
```

The first suite exercises cache hits, dependency invalidation, missing outputs,
generation failures, source/header synchronization, all release channel arguments
and packaging failures using temporary fixtures. The Xcode smoke test runs the
actual archive script against a small unsigned universal app, checking its channel
condition and dSYM with default settings and with compilation caching enabled.
It does not replace validation of a signed ImpulseM archive on the release runner.

Version numbers are bumped manually at release time, not per build: run
`tools/bump_build_number.sh Telegram-Mac/Info.plist` to increment `CFBundleVersion`, then
`tools/sync_share_version.sh Telegram-Mac/Info.plist TelegramShare/Info.plist` so the share
extension matches (App Store validation requires it). These used to run from a build phase on the
`Telegram` target, which rewrote `Info.plist` on every build and so made every incremental build
re-package and re-link the app.

## Localized strings

`Telegram-Mac/en.lproj/Localizable.strings` is UTF-16; keep it that way when editing.
After adding strings, regenerate the Swift accessors:

```
brew install swiftgen
sh tools/swiftgen.sh
```

which writes `packages/Localization/Sources/Localization/Localizable.swift`.

## Running package tests

The Swift packages can be tested on their own without building the app, for example:

```
cd packages/ApiCredentials && swift test
cd packages/TGUIKit && swift build
```

## Troubleshooting

- **"Bad CPU type in executable" while building tde2e** on Apple Silicon: install
  Rosetta 2 (`softwareupdate --install-rosetta --agree-to-license`).
- **CMake complains about `cmake_minimum_required`**: export
  `CMAKE_POLICY_VERSION_MINIMUM=3.5` before running `configure_frameworks.sh`.
- **Xcode reports a missing library or `SharedHeaders` directory**: a library was skipped
  because a stale `core-xprojects/<lib>/build` directory existed. Delete it and rerun
  `configure_frameworks.sh`.
- **`duplicate symbol` or `library not found` for a native library**: delete
  `core-xprojects/<lib>/build` and rerun `configure_frameworks.sh`; the stamp is rewritten
  only after its outputs pass the checks.
- **RLottie or CodeSyntax not found**: you opened `Telegram.xcodeproj`. Open the
  workspace instead.
- **TelegramCore fails to build right after a `telegram-ios` submodule bump**: newly
  imported modules must be listed in
  `submodules/telegram-ios/submodules/TelegramCore/Package.swift`; add the missing
  dependencies there.

## If you want to develop a fork

1. Build the app first, as above.
2. Use your own API credentials for the fork. The built-in `apiId` 4 (`impulsem-desktop`)
   belongs to the ImpulseM desktop clients.
3. Put your `apiId`, `apiHash`, `bundleId` and `teamId` into
   `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`. The brand constants that the
   file reads, such as `apiId` and the placeholders, are in `ImpulseBrand.swift` in the same
   package.
4. Search the project for `net.impulsem.messenger` and `TEAM_ID_PLACEHOLDER` and replace them
   with your bundle identifier and team (project settings, entitlements, app group).
5. Replace `SFEED_URL` in the xcconfig files with your update feed. The Sparkle public EdDSA key
   is `Resources/keys/ed_pub.txt`; generate your own key pair and keep the private key out of
   the repository.
6. Follow the rules in the README's "Forking" section: do not call the fork Telegram and
   do not reuse the logo.
7. Questions: open an issue at https://github.com/Impulse-m/ImpulseM.Client.Desktop.Mac/issues/new.

## Performance labs and CI releases

Performance labs remain available in Debug builds. PerfLab implementation, NetworkLab and feature lab entry points are compiled only with `DEBUG`; CI archives use Release for every distribution channel.

Before deployment, `buildbox/verify-build.sh` runs `buildbox/verify-no-labs.py` against the built app. It rejects lab-named artifacts and lab symbols or launch markers in every Mach-O binary, including embedded frameworks and extensions. Debug metadata is removed from a temporary inspection copy so excluded source-file references do not cause false positives; the signed app is untouched. A failed check prevents deployment. Keep this check in place when changing lab code or build flags.

Run its native fixture checks with `python3 -m unittest discover -s buildbox -p 'test_verify_no_labs.py' -v`. These exercise clean, contaminated, stripped and nested binaries. They do not replace verification of the actual CI archive.
