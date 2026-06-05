# Oh Hell Multiplayer Starter for Godot 4

This starter ports the rules from `oh-hell_1.html` into GDScript and wraps them in a host-authoritative multiplayer shape.

## What is included

- `scripts/game_rules.gd`: deck creation, shuffle/deal, round sequence, legal-card checks, trick winner logic, and scoring.
- `scripts/net.gd`: simple ENet host/join helpers.
- `scripts/main.gd`: a minimal playable table UI and RPC flow.

## Current multiplayer model

The host is authoritative. Clients submit bids and card plays to the host, and the host validates/mutates table state. Each peer receives only its own private hand plus public table state.

The current seat assignment is intentionally simple:

- Host is seat 1.
- Joined peers fill seats 2, 3, 4, and so on.
- The lobby supports 2 to 10 players.
- The host chooses player count and max cards before starting.

## Next things to build

1. Add reconnect handling and explicit turn timers.
2. Add validation tests for `game_rules.gd`.
3. Add an online relay/lobby option for games outside local Wi-Fi.

## Running it

Open `outputs/oh_hell_godot_starter` as a Godot 4 project and run `scenes/main.tscn`.

For local multiplayer testing, run one instance as Host and a second instance as Join localhost. Two-player games are supported, which makes quick testing much easier.

For a full four-seat local test on Windows, run:

```powershell
.\launch_local_4.ps1
```

That opens one host window and three localhost client windows.

## iOS

The project is prepared for mobile-style scaling and landscape play. See `IOS_EXPORT.md` for the Mac/Xcode steps needed to deploy it to an iPhone or iPad.
