# What is this?

This is all the software behind my home system. It contains *multiple* different Flutter apps, a big Node.js server, and a lot of tools. Here's what everything does, listed by directory starting at the root:

- `android`: Contains resources for the app for the Android dashboard. I use this to lock some old tablets to my app to make it a kiosk-like device.
    - `flutter`: The app itself. I made a separate folder because I was considering using just Kotlin, but eventually I just went with Flutter.
    - `icons`: Contains app icons.
- `app`: This is the big boy home app. It has a *ton* of Dart files and even more lines of code. The code is in `lib` and most of the code is in both `main.dart` and `dashboard.dart`.
- `assets`: Contains assets like fireplace videos and sounds.
- `bin`: Add this to `PATH` for some global commands for the home app.
    - `fancontrol`: For the host iMac, a shortcut to `fancontrol.sh` in `tools`.
    - `homebuildall`: Shortcut to `buildall.sh` in `tools`.
- `build`: Linux app build for the host. Generated with `buildall`.
- `cert`: The directory to put SSL certificates in. These don't need to be signed by a CA.
- `conf`: An old, deprecated directory containing `.conf` files for DNS and proxy services, when I was trying to make a DNS server and a proxy.
- `logs`: Generated logs.
- `public`: The web app generated with `buildall`.
- `server`: Contains the big Node.js server. I won't go through every single file here.
    - `services`: Contains some separate files for certain things.
        - `announcer.js`: Handles taking a text input, converting it to an audio file, and playing said audio file.
    - `data.json`: Contains data. This is auto-generated and does not need to be recreated.
    - `homekit-*.json`: Contains data related to HomeKit devices.
    - `localpkg.cjs`: Contains a lot of utilities for use with all files.
    - `server.js`: Manages starting the server and processing requests.
    - `socket.js`: Handles client connections and data streams.
    - `tv-apps.json`: A static database of Vizio TV apps.
    - `tv-data.json`: Some extra settings for Vizio stuff.
- `spotify`: Contains Spotify and `spotifyd` related stuff.
- `temp`: Temporary files.
- `tools`: Some extra tools I use to help streamline development.
    - `python3.9`: A Python 3.9 virtual environment, because it was the only solution I knew of.
    - `buildall.sh`: Generates web and Linux builds of the main app, and copies them to `build` and `public`.
    - `codetest.dart`: Scans the main app and makes sure some things are correct for release.
    - `countlines.dart`: A fun little script to count the lines and files of codr I've made. Run with `--json` to output as JSON.
    - `deployweb.sh`: Web part of `buildall`.
    - `deployapp.sh`: App part of `buildall`.
    - `dnscheck.sh`: Deprecated, for a DNS server.
    - `fancontrol.sh`: Used for controlling the fan speed on my old iMac.
    - `followdns.sh`: Deprecated, for a DNS server.
    - `grantnode.sh`: Grants Node.js permissions for stuff like using port 80.
    - `speedtest`: speedtest.net CLI tool.
    - `webcam.sh`: Ran by the server to capture webcam data.
- `url`: An old, deprecated directory related to proxying.
- `.env`: Contains environmental variables.
- `sample.env`: Explains each environmental variable for when I deploy.
- `config.json`: Configuration for the server.
- `notes.md`: Personal notes for developers.

# Credits

## People and Companies

- Calebh101, me
- My family for supporting me and this project
- Vizio for having the most hackable TV ever
- ecobee for absolutely nothing, I had to go through Apple's HomeKit while setting up a separate Python environment to communicate with my thermostat

## Externally Sourced Software

There are some third-party scripts I took to use for this project or personal use only.

- `tools` directory:
    - fancontrol.sh: I got this from [Github: JuampiCarosi/fan-control](https://github.com/JuampiCarosi/fan-control) and slightly modified it to suit my needs.
    - speedtest: This came from the speedtest.net official tool. I did not modify this.
- `spotify` directory:
    - `spotifyd`: Used for creating a Spotify host. I did not modify this.

# Changelog

## 1.0.0A - 3/4/25 - Initial release

- Initial release

## 1.0.0B - 3/21/25 - Critical update

- Fixed a bug with announcements/contacts not refreshing

## 1.0.1A - 3/21/25 - Minor update

- A new Last Refreshed in Settings
- Other minor changes

## 1.0.1B - 3/22/25 - Minor update

- New icons in volume/brightness section, with a mute button
- Added `enable` key in config.json for night mode, which can disable the schedule
- Fixed a bug that was causing the app to display announcement times as UTC

## 1.1.0A - 3/24/25

- Internet Test section for testing Internet connection, Internet speed, router availability, and server availability
- New colored graph and axis labels in the glucose monitor
- Colored Graphs setting
- New clock for kiosk
- Other bug fixes and small improvements

## 1.1.0B - 3/25/25

- Using backend to ping router instead of frontent
- Small coloring updates for the Internet Test results

## 1.1.0C - 3/29/25

- Small update to allow suspending the host (instead of a power down)

## 1.1.1A - 4/2/25

- Fireplace sound effects
- Coloring update for glucose monitor - now fetches ranges and glucose-related settings from server
- Announcements don't show if there are no announcements available

## 1.2.0A - 5/28/25

- The home server code is officially open source! I wanted to make sure all sensitive info was contained before moving it to a public repository.