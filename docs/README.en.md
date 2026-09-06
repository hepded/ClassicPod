# ClassicPod

**A retro music player you can turn around.** Native macOS app, Swift 6, macOS 14+ deployment target. Version 0.3.0 beta. [MIT license](../LICENSE) · [Русский](../README.md).

![Built-in ClassicPod model rotating](media/turntable.gif)

SceneKit renders a fully modeled metal body, click wheel, rear shell and ports. SpriteKit renders the live 320×240 display. Local files play through AVQueuePlayer; Spotify audio plays on a Spotify Connect device, not inside ClassicPod.

## Build

On a Mac with Swift 6 and the macOS SDK, run these commands from the project root:

```sh
bash scripts/build-app.sh
open dist/ClassicPod.app
```

The generated app is ad-hoc signed, not notarized. The locally tested binary is Apple Silicon, not universal. Building with Xcode/XCTest requires full Xcode. Never disable Gatekeeper globally to run the app.

## Controls and language

- Drag the body to rotate it; Option-drag moves the window.
- Rotation Inertia in Settings enables a gentle coast after release. A new touch, Escape, hiding the window or turning it off stops the coast. The saved preference also respects macOS Reduce Motion.
- Escape restores the front view; the next Escape goes back in the menu.
- Rotate the click wheel to scroll. Center / Return selects; Space toggles playback; Left / Right skips tracks.
- In Now Playing, the wheel controls volume. Select switches between volume and seeking.
- Right-click for Settings, Import, Front View, Always on Top and Quit.
- Settings → Language: System Default, English or Русский. The choice is saved and applies without restarting, changing playback or resetting the model. System Default follows the first supported macOS preferred language, falling back to English.
- Music titles, artists, playlists and device names are not translated. Native macOS dialogs and system-generated error text follow the system language.

## Local music

Import files or folders, including drag-and-drop. Supported extensions: MP3, M4A, FLAC and WAV; actual codec support depends on AVFoundation. Files are not copied. The library stores bookmarks and metadata locally. Use Locate File if an original file is missing.

## Spotify

1. Create your own app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard). Use its Client ID; never embed a client secret.
2. Register exactly `http://127.0.0.1:43821/callback` as a redirect URI. Check current account access and Development Mode restrictions.
3. Enter the Client ID in Settings and sign in. Web API playback requires Premium and a network connection.
4. Open Spotify manually and make a Connect device available. Choose a device in the Spotify menu, or let the first playback command select the single active available device.
5. Select a song from Liked Songs or a playlist. The chosen device ID remains pinned for subsequent commands.

Connect is the default. Commands never fall back to Apple Events after failure. The optional Legacy Bridge requires the running macOS client and Automation permission; it **may bring Spotify to the foreground**. Use Connect to avoid that known legacy path. ClassicPod does not hide Spotify or force focus back afterward.

Tokens stay in Keychain; Client ID is stored in UserDefaults. Signing out deletes local tokens. [Data and permissions](../PRIVACY.md) (Russian). Spotify's [PKCE documentation](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow) describes the authentication flow.

## Tests and beta limits

```sh
bash scripts/check.sh
swift test
```

The first command includes SceneKit rendering and requires a graphical macOS session. It uses fixtures, temporary audio and a loopback listener, not your Spotify account. `swift test` requires XCTest from full Xcode. The prepared GitHub workflow has not yet been run on GitHub.

Known limits: up to 100 Spotify URIs per queue submission; no library search, shuffle/repeat or restoration of window/orientation/queue across launches. Device selection is session-scoped. No complete test matrix for macOS 14, Intel, multi-display setups, sleep/wake, all audio codecs or every Spotify state. [Detailed validation](../VALIDATION.md) (Russian).

Unofficial independent project, not affiliated with Apple or Spotify. The repository includes no music, album art or extracted Apple models/sounds. MIT covers the project's code and original assets, not third-party media or trademarks.
