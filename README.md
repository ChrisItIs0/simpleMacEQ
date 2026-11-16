# SimpleMacEQ

A menu bar equalizer for macOS that remembers a separate 16-band EQ profile for
each audio output device.

Turn the EQ on for your desk speakers and tune them; headphones, the MacBook
speakers and every other output stay untouched. When you switch the system
output back to the speakers, their profile is applied automatically.

## Requirements

- macOS 14.2 or later
- Xcode 15.2 or later (or the matching command line tools) to build

## Build and run

```bash
./scripts/build-app.sh
```

```bash
open build/SimpleMacEQ.app
```

To keep it around, copy `build/SimpleMacEQ.app` to `/Applications` and tick
**Launch at login** in the app.

The first time you enable the EQ, macOS asks for permission to capture system
audio. The EQ cannot work without it. If you deny it, you will hear silence on
that device while the EQ is switched on; switch the EQ off, or allow the app
under System Settings → Privacy & Security → Screen & System Audio Recording.

The build is ad-hoc signed, so macOS asks for that permission again after each
rebuild.

## Using it

Click the slider icon in the menu bar.

- **EQ for this device** switches the equalizer on or off for the current
  output device. The setting is remembered per device.
- The 16 sliders cover 20 Hz to 20 kHz in 2/3-octave steps, ±12 dB each.
- **Preamp** lowers (or raises) the overall level. Lower it when you boost
  bands, to avoid clipping.
- **Reset** sets all bands and the preamp back to 0 dB.

## How it works

No audio driver is installed. For a device with the EQ switched on, the app
creates a Core Audio process tap that captures and mutes all system audio, and
a private aggregate device that plays the tapped audio through the filters to
the real output device. The system output device does not change, so the
volume keys behave as usual. For devices without an enabled profile no tap
exists and audio is not touched at all.

- `Sources/EQCore` – the biquad filter cascade and the profile store
- `Sources/SimpleMacEQ` – Core Audio routing, device tracking and the menu bar UI

## Tests

```bash
swift test
```
