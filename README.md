# VacuumTube for iPad

An unofficial port of [VacuumTube](https://github.com/shy1132/VacuumTube) to iPad. It wraps YouTube Leanback (the console and Smart TV version of YouTube) in a native app, with touch controls, a built-in adblocker and SponsorBlock.

The desktop app (Windows, macOS, Linux) lives upstream: see the [original VacuumTube README](https://github.com/shy1132/VacuumTube#readme) for its downloads, settings and flags.

## What exactly is this?

YouTube Leanback is an official HTML5 interface, which YouTube serves only to console and TV apps. VacuumTube for iPad loads it in a `WKWebView` that identifies itself as a TV app, and reuses the upstream VacuumTube page modules (adblock, settings and so on) bundled for WebKit.

## Features

- Touch controls for Leanback: tap, scroll the shelves with a finger, swipe from the right edge to go back, swipe down to close the player
- Ad blocking, using the upstream adblock module
- [SponsorBlock](https://sponsor.ajay.app/): sponsored segments are skipped automatically
- Background playback through Picture in Picture
- In-app mini player
- Playback speed stays the same from one video to the next
- No autoplay at the end of a video
- Works with Shorts
- AV1 is turned on by default on a device
- The page reloads on its own if the web content process crashes

## Limitations

- iPad only
- Requires iPadOS 27.0 or later
- Video quality tops out at 720p in WebKit
- There are no prebuilt builds: you build and sign the app yourself

## Building from Source

You need a Mac with Xcode and Node.js.

```sh
git clone https://github.com/krotghar/VacuumTube-iPad
cd VacuumTube-iPad/ios

# Install esbuild
npm i

# Rebuild the page bundle (VacuumTube/leanback-bundle.js)
npm run build-js
```

The bundle is checked in. Rebuild it after you change `ios/js/` or the upstream modules in `src/preload/`.

Then open `ios/VacuumTube.xcodeproj` in Xcode. Set your own signing team and bundle identifier (the project ships with `com.krotghar.VacuumTube`), then run the app on an iPad or in the iPad simulator.

## Credits

Built on top of [VacuumTube](https://github.com/shy1132/VacuumTube) by shy1132. See [LICENSE](LICENSE).

SponsorBlock data comes from the community database at [sponsor.ajay.app](https://sponsor.ajay.app/), licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
