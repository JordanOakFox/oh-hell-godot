# iOS Export Notes

Yes, this Godot project can run on iOS, but the final export/sign/deploy step must happen on macOS with Xcode installed.

## What you need

- A Mac with Xcode installed.
- Godot 4.6.x on that Mac.
- Godot export templates installed from `Editor > Manage Export Templates`.
- An Apple Developer account or free Apple ID signing in Xcode for local device testing.
- A real bundle identifier, such as `com.yourname.ohhell`.
- Your Apple Team ID. Godot expects the 10-character ID, not the display name shown in Xcode.

## Export from Godot

1. Open this project folder in Godot on the Mac.
2. Go to `Project > Export`.
3. Click `Add...` and choose `iOS`.
4. Fill in:
   - `App Store Team ID`
   - `Bundle Identifier`
   - App name/icons later, when you have final assets.
5. Export to an empty folder with a simple project name like `OhHellIOS`.
6. Open the exported `.xcodeproj` in Xcode.
7. Select your connected iPhone or iPad and press Run.

## Networking note

The current prototype uses Godot ENet host/client networking. That should be fine for local Wi-Fi testing, but iOS devices may ask for Local Network permission. For playing over the internet, the game should eventually use a dedicated relay/server or matchmaking layer instead of one phone hosting directly.

## Useful official docs

- Godot iOS export guide: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html

