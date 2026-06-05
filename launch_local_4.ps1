$Godot = "C:\Godot\Godot_v4.6.3-stable_win64.exe"
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommonArgs = @("--path", $Project, "--audio-driver", "Dummy", "--rendering-driver", "opengl3")

Start-Process -FilePath $Godot -ArgumentList ($CommonArgs + @("--", "--host"))
Start-Sleep -Milliseconds 800

1..3 | ForEach-Object {
    Start-Process -FilePath $Godot -ArgumentList ($CommonArgs + @("--", "--join"))
    Start-Sleep -Milliseconds 300
}
