# Oh Hell

Online multiplayer Oh Hell built in Godot 4. The game supports Windows and macOS clients, bot-filled tables, profiles, reconnecting by profile, 3D table views, music/SFX controls, and a dedicated Godot server.

## What is included

- `scripts/game_rules.gd`: deck creation, shuffle/deal, round sequence, legal-card checks, trick winner logic, and scoring.
- `scripts/net.gd`: simple ENet host/join helpers.
- `scripts/main.gd`: the lobby, table UI, dedicated-server mode, and RPC flow.

## Current Multiplayer Model

The server is authoritative. Clients submit bids and card plays to the server, and the server validates/mutates table state. Each peer receives only its own private hand plus public table state.

- Joined peers fill seats 1, 2, 3, and so on.
- The lobby supports 2 to 10 players.
- Empty seats can be filled with bots.
- The first joined player can manage lobby settings on the dedicated server.
- Rejoining with the same saved profile returns a player to their previous seat when possible.
- Bot style can be set to Casual, Smart, or Ruthless from Settings.
- Players can open an in-game round history panel during play.
- The table host can end a running game and return everyone to the lobby.
- `M` toggles all game audio, and Settings can mute SFX separately.
- Hold right mouse button and drag during play to look around the table.

## Current Online Server

The public test server is:

```text
147.224.130.79:24567
```

New client builds show named public lobbies. `Family Table` uses this address by default. For local testing, open `Advanced`, then replace the address with `127.0.0.1`.

## Next Things To Build

1. Add reconnect handling and explicit turn timers.
2. Add validation tests for `game_rules.gd`.
3. Add Steam achievements/invites after the base Steam page and builds are ready.

## Running it

Open this folder as a Godot 4.6 project and run `scenes/main.tscn`.

For local multiplayer testing, run one instance as Host and a second instance as Join localhost. Two-player games are supported, which makes quick testing much easier.

For a full four-seat local test on Windows, run:

```powershell
.\launch_local_4.ps1
```

That opens one host window and three localhost client windows.

## iOS

The project is prepared for mobile-style scaling and landscape play. See `IOS_EXPORT.md` for the Mac/Xcode steps needed to deploy it to an iPhone or iPad.
