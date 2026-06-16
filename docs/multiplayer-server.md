# Oh Hell Multiplayer Server

The game can run with a dedicated Godot server. The server owns the game state, and players connect as clients.

## Local test on one machine

Start the server:

```powershell
Start-Process -FilePath 'C:\Godot\Godot_v4.6.3-stable_win64_console.exe' -ArgumentList @('--headless','--path','C:\Users\coldf\Documents\GitHub\oh-hell-godot','--audio-driver','Dummy','--rendering-driver','opengl3','--','--server','--players=2','--cards=2','--map=pirate','--port=24567')
```

Start a client on the same machine:

```powershell
Start-Process -FilePath 'C:\Godot\Godot_v4.6.3-stable_win64.exe' -ArgumentList @('--path','C:\Users\coldf\Documents\GitHub\oh-hell-godot','--audio-driver','Dummy','--rendering-driver','opengl3','--','--join','--address=127.0.0.1:24567')
```

## Local Wi-Fi

Run the server on one computer, then connect from another computer using the server computer's local IP:

```text
192.168.1.50:24567
```

Windows must allow Godot through the firewall on private networks.

## Internet hosting

To host from a home PC, forward UDP port `24567` on the router to the server computer, then players join:

```text
your-public-ip:24567
```

You can choose a different port with `--port=PORT`. If you do, use the same port when joining and in the router UDP port forward.

## Dedicated server command options

```text
--server              Run as dedicated server
--players=2..10       Starting table size
--cards=1..max        Starting max cards
--map=pirate          pirate, space, living_room, or jungle
--port=24567          UDP port for clients
```
