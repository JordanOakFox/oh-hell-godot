# Steam Readiness Checklist

This project can be prepared for Steam before the Steam Direct fee is paid. The first goal is a clean public test build that behaves like a product, then we add Steam-specific features.

## Done In The Project

- Product name is `Oh Hell` instead of the old starter name.
- Windows and macOS export presets exist.
- The client defaults to the public server at `147.224.130.79:24567`.
- Clients and servers publish a game version so mismatched builds can warn players.
- A dedicated server can run through the `oh-hell` systemd service.

## Before Creating The Steam Page

- Pick the final public name and confirm it is searchable and not confusingly close to another card game.
- Make a real app icon for Windows, macOS, and Steam.
- Capture clean screenshots from the current maps.
- Write the short description, long description, and feature bullets.
- Decide whether the first Steam release is free, paid, or a closed playtest.

## Before Release

- Add a simple settings screen for audio/video and server address.
- Add reconnect handling for dropped players.
- Add clearer server-full and version-mismatch screens.
- Build signed/notarized macOS packages or distribute through Steam's normal depot flow.
- Run a full test night with Windows and macOS clients before uploading release depots.

## Steamworks Later

- Steam achievements for wins, perfect rounds, and total games played.
- Steam rich presence showing lobby or in-game state.
- Steam invites or lobby integration if we want joining friends to be one-click.
- Cloud save for profile stats if local profile files become a problem.
