# iOS Build Notes

This project is now prepared for an iOS test build: gameplay card selection supports touch taps/drags, the game is locked to landscape, and the current online lobbies use the Oracle dedicated servers instead of phone-hosted networking.

The final iPhone/iPad app still has to be exported on your Mac with Godot and opened in Xcode for signing.

## What You Need On The Mac

- Godot 4.6.x for macOS.
- Xcode from the Mac App Store.
- Godot export templates installed from `Editor > Manage Export Templates`.
- Your GitHub project cloned onto the Mac.
- An Apple ID signed into Xcode. A paid Apple Developer account is needed later for TestFlight/App Store sharing.
- A bundle identifier. Use something like `com.jordanoakfox.ohhell`.

## Update The Mac Project

Open Terminal on the Mac and run:

```bash
cd ~/Documents/GitHub/oh-hell-godot
git pull
```

If the repo is somewhere else, use that folder instead.

## Export From Godot

1. Open Godot on the Mac.
2. Open the `oh-hell-godot` project.
3. Go to `Editor > Manage Export Templates` and install templates if Godot asks.
4. Go to `Project > Export`.
5. Click `Add...` and choose `iOS`.
6. Use these starting settings:
   - Name: `iOS`
   - Bundle Identifier: `com.jordanoakfox.ohhell`
   - App Store Team ID: your Apple team ID from Xcode
   - Export Filter: `Export all resources in the project`
   - Texture format: leave ASTC/ETC2 enabled if available
7. Export to a new empty folder, for example `~/Desktop/OhHellIOS`.
8. Open the exported `.xcodeproj` file in Xcode.

## Run On Your iPhone Or iPad

1. Plug the device into the Mac.
2. In Xcode, select the real iPhone/iPad as the run target.
3. Click the project in the left sidebar, then the app target.
4. Under `Signing & Capabilities`, turn on automatic signing and pick your team.
5. Press Run.

If iOS asks for network permission, allow it. The public lobby buttons need internet access to reach the game server.

## Server Reminder

When the game version changes, update the Oracle server too:

```bash
ssh -i ~/.ssh/oh-hell-oracle ubuntu@147.224.130.79
cd ~/oh-hell-godot
git pull
sudo systemctl restart oh-hell oh-hell-practice oh-hell-big
sudo systemctl status oh-hell oh-hell-practice oh-hell-big
```

## Useful Links

- Godot iOS export guide: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- Apple TestFlight: https://developer.apple.com/testflight/
