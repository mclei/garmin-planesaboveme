# Planes Above Me

### What plane is that?

Point your wrist at an aircraft in the sky and find out what it is. **Planes
Above Me** shows the live air traffic around you on a compass, and for the one
you're facing it tells you its **destination**, **aircraft type**, altitude,
speed and operator.

It finds anything broadcasting ADS-B overhead — **airliners and small
airplanes, helicopters, business jets, cargo and military flights** — referred
to collectively here as *aircraft*.

Built for the **Garmin Venu X1** (square display); works on any modern Connect
IQ device added to the manifest.

## Features

- **Compass radar** — every aircraft within range drawn as a triangle pointing
  along its ground track, in **all directions** (full 360°), distance-scaled.
- **What you're facing** — the aircraft in front of you is shown large with its
  callsign, **destination** (e.g. "FRA → JFK New York"), **type** (e.g. "Airbus
  A320 - Lufthansa"), altitude, speed and distance.
- **Detail page** — tap (or the Start button) for the full picture: origin and
  destination airports, manufacturer, ICAO type, operator, registration,
  country, altitude, speed and ground track. Scrollable.
- **Lock** — on the detail page press **Start** to lock onto one aircraft; the
  arrow then keeps pointing at it as you turn, so you can follow it across the
  sky. Press Start again to unlock.
- **Nearby list** — swipe up for all aircraft in range, nearest first, with
  altitude.
- Search radius (default **10 km**) and refresh interval configurable.

## Data sources (free, no API keys)

| Data | Source | Notes |
|------|--------|-------|
| Aircraft positions | [OpenSky Network](https://opensky-network.org) | Anonymous access; positions, altitude, speed, ground track and callsign. Daily request budget applies — default refresh is 30 s. |
| Type & route | [adsbdb.com](https://www.adsbdb.com) | Free, keyless. Resolves the **focused** aircraft's type (by Mode-S address) and route (by callsign) on demand and caches it, so request volume stays low. |

Requests go through the **paired phone** (Garmin Connect Mobile must be running
with internet). Without it you'll see an error on the status line.

## Usage

| Input | Action |
|-------|--------|
| Tap the screen, or the **Start/Enter button** | Detail page of the aircraft you're facing |
| Swipe up | Nearby-aircraft list (select one for its detail page) |
| On the detail page: **Start** | Lock / unlock the aircraft; swipe or buttons to scroll; Back to close |
| Back | Exit |

The status line shows your heading, the aircraft count (or loading/error
state); a leading `~` means the position is still approximate.

## Building & installing

Same toolchain as any Connect IQ app:

1. Install the **Connect IQ SDK Manager** (developer.garmin.com/connect-iq/sdk)
   + a JRE, download the latest SDK and the **Venu X1** device files.
2. Generate a developer key once:
   ```sh
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
       -in developer_key.pem -out developer_key.der
   ```
3. Build: `monkeyc -d venux1 -f monkey.jungle -o Planes.prg -y developer_key.der`
4. Simulator: `connectiq` then `monkeydo Planes.prg venux1` (set a GPS position).
5. Sideload: copy `Planes.prg` into the watch's `GARMIN/Apps` folder over USB,
   then safely eject — the watch imports it during "Verifying Connect IQ Apps".

The launcher icon can be regenerated with `python3 scripts/make_icon.py`.

## CI

`.github/workflows/build.yml` builds on every push/PR and uploads
`Planes.prg` as an artifact. Set a repository secret `CIQ_DEVELOPER_KEY`
(base64 of your `developer_key.der`) so every build is signed with the same
key — otherwise each rebuild is a fresh app and on-watch settings reset.

## Sister app

POIs on the ground (historic sites, restaurants, culture, …) live in a
separate app, **POI Finder** — this app is aircraft-only on purpose.
