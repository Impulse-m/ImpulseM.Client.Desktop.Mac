# ImpulseM for macOS

ImpulseM for macOS is the native macOS client of the ImpulseM messenger. The source is open, and anyone may build and host it.

## How to build

Full instructions, requirements and troubleshooting are in [INSTALL.md](INSTALL.md). In short:

1. Install full Xcode 26 or newer, Homebrew and a Rust toolchain (rustup). On Xcode 27, apply the local changes in [XCODE27.md](XCODE27.md) first.
2. Clone the repository and enter it:
   ```
   git clone https://github.com/Impulse-m/ImpulseM.Client.Desktop.Mac.git
   cd ImpulseM.Client.Desktop.Mac
   ```
3. Prepare the machine, check out the submodules and build the native libraries once:
   ```
   sh scripts/setup_build_env.sh --build
   ```
4. Open `Telegram-Mac.xcworkspace` in Xcode, not `Telegram.xcodeproj`, and build the `ImpulseM` scheme. Or build from the command line without signing:
   ```
   xcodebuild -workspace Telegram-Mac.xcworkspace -scheme ImpulseM -configuration Debug build \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
   ```

The repository contains no Apple Developer team, so builds are unsigned.

## Build variables

The build reads these variables. Set them as environment variables or build settings with the same names. CI takes them from the organisation variables `${{ vars.IMPULSEM_* }}`. They are not secrets.

| Variable | What it does | When it is empty |
|---|---|---|
| `IMPULSEM_RPC_URL` | Base URL of the transport host, for example `https://rpc.example.org`. The client builds its websocket endpoints from it. | CI app builds fail with a clear message. Local and test builds start, make no connection attempt and stay not connected. |
| `IMPULSEM_LINK_HOST` | Host without scheme of public share links, for example `o.example.org`. Used to build share links and to recognise links in messages. | No host is recognised statically. Links rely on the server prefix and the app's URL scheme, and UI that needs the host to build a link is hidden. |
| `IMPULSEM_MACOS_FEED_URL` | Base URL of the update feeds, for example `https://macos.example.org`. The app reads `updates/versions.xml`, `beta/versions.xml` and `alpha/versions.xml` below it. | Update checks are off and the update UI is hidden. |

## License

This project is licensed under the GNU General Public License, version 2.0. See [LICENSE](LICENSE) for the full text.
