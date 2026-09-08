# media-bridge

Local background service for Dynamic Island that reads Windows media playback info, controls volume, and plays UI sound effects with audio ducking.

## How it works

Runs a local HTTP server on http://127.0.0.1:45455 and returns JSON with current track title, artist, album, album art (base64 and file path), dominant cover color, per-app volume, and real-time audio peak levels.

Supports Spotify, Apple Music, Yandex Music, YouTube, browser audio, and other Windows media apps.

## Usage

Just download and run `media_bridge.exe` [from the release](https://github.com/qhols/DynamicIsland/releases/latest). Make sure the `sounds` folder is placed in the same directory alongside the executable.

It will run silently in the background and start listening on port 45455. If launched again, it automatically cleans up any previous instance and takes over the port.

Alternatively, you can run the PowerShell script directly:
```
start_bridge.bat
```

## Endpoints

- `GET /media` - returns current track info, cover, dominant color, volume, and waveform
- `GET /media/playpause` - toggle play/pause
- `GET /media/next` - next track
- `GET /media/prev` - previous track
- `GET /media/shuffle` - toggle shuffle mode
- `GET /media/repeat` - toggle repeat mode (None -> List -> Track)
- `GET /media/like` - toggle like on Spotify (sends Alt+Shift+B)
- `GET /media/volup` - increase media volume (+5%) with haptic notch sound feedback
- `GET /media/voldown` - decrease media volume (-5%) with haptic notch sound feedback
- `GET /sound?name=<name>&vol=<0.0-1.0>&duck=<0.0-1.0>&force=<0|1>` - plays a sound effect from the `sounds/` folder with optional audio ducking
- `GET /focus` - checks if Dota 2 is currently focused in the foreground

## Building from source

Requirements: PowerShell 5.1+ and [ps2exe](https://github.com/MScholtes/PS2EXE).

```powershell
Invoke-ps2exe -inputFile media_bridge.ps1 -outputFile media_bridge.exe -iconFile dynamic_island.ico -x64 -noConsole
```
