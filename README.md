# SimpleMacEQ

A tiny menu bar equalizer for macOS that keeps a separate 16-band EQ profile
for each output device. Tune your speakers once; headphones and everything
else stay untouched.

- 16 bands from 20 Hz to 20 kHz, ±12 dB, plus a preamp
- Drag a slider, or hover and use the scroll wheel
- No audio driver, and your volume keys keep working

## Build

Requires macOS 14.2+ and Xcode 15.2+ (or the command line tools).

```bash
./scripts/build-app.sh
open build/SimpleMacEQ.app
```

Copy the app to `/Applications` to keep it, or run `./scripts/build-dmg.sh`
for a disk image. Pushing a `v*` tag publishes a GitHub release with the `.dmg`. On first use, allow system
audio capture: System Settings → Privacy & Security → Screen & System Audio
Recording.

## How it works

A Core Audio process tap captures system audio, and a private aggregate device
plays it through the filters to your real output. Devices without the EQ
switched on are never touched.

Run the tests with `swift test`.
