# macOS Friend Build

The macOS client build is exported as:

```text
builds/macos/OhHell-macOS.zip
```

To play:

1. Unzip `OhHell-macOS.zip`.
2. Open the `.app`.
3. Join the server:

```text
147.224.130.79:24567
```

Because this build is not Apple-notarized, macOS may block it the first time.

If that happens:

1. Right-click the app.
2. Choose **Open**.
3. Choose **Open** again in the warning dialog.

If macOS still blocks it, open Terminal in the folder containing the app and run:

```bash
xattr -dr com.apple.quarantine OhHell.app
```

Then open the app again.

Crossplay works through the shared Godot dedicated server. Windows and macOS clients can join the same server as long as they are built from compatible project versions.
