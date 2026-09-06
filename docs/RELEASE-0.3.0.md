# ClassicPod 0.3.0 Beta

A native macOS music player with a fully rotatable retro body, a working click wheel and a live display.

## Highlights

- Detailed 3D body with brushed aluminum, polished metal, ports and refined lettering.
- Arcball rotation with gentle, optional inertia; respects macOS Reduce Motion.
- Transparent desktop window, Option-drag to move and Escape for the front view.
- Local music import without copying your files; AVFoundation playback.
- Spotify library browsing and Connect playback, with no automatic Apple Events fallback.
- English and Russian interfaces, persistent language selection and a custom Retina app icon.

## Getting started

The attached app is for **Apple Silicon** and is **ad-hoc signed, not notarized**. macOS 14 is the deployment target; not every macOS release or hardware configuration has been tested. Review the source before running an unofficial build. Alternatively, build on your own Mac with Swift 6 and the macOS SDK:

```sh
bash scripts/build-app.sh
open dist/ClassicPod.app
```

Spotify Web API playback requires Premium, network access and your own configured Spotify Developer Client ID. Start Spotify manually and select a Connect device. No account credentials are included in the release.

## Known limitations

- This is a beta, not a production-stability guarantee.
- Connect queue submission is limited to 100 URIs; no automatic continuation beyond that batch.
- The optional legacy desktop bridge can bring Spotify to the foreground. Prefer Connect.
- No search, shuffle/repeat, or restoration of window position, model orientation and queue after relaunch.
- Intel, the full audio-codec matrix, prolonged playback, multi-display behavior and all Spotify error states have not been fully tested.
- GitHub CI is prepared; its first hosted run must be checked after publication.

22 core checks and local integration checks pass. See VALIDATION.md and the English guide in the repository for the exact scope; automated fixtures do not replace live Spotify testing.

MIT licensed. Independent, unofficial project; not affiliated with Apple or Spotify. No music, album art or proprietary Apple sound/model assets are included.
