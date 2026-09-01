# media-bridge

Local background service for Dynamic Island that reads Windows media playback info and audio waveform data.

## How it works

Runs a local HTTP server on http://127.0.0.1:45455 and returns JSON with current track title, artist, album, album art (base64 and file path), dominant cover color, and real-time audio peak levels.

Supports Spotify, Apple Music, Yandex Music, YouTube, browser audio, and other Windows media apps.

## Usage

Just run `MediaBridge.exe` from the release. It will start listening on port 45455.

## Building from source

Requirements: g++ (MinGW-w64) or CMake.

Using GCC / batch script:
```cmd
cd cpp_source
build.bat
```

Or manually:
```cmd
g++ -std=c++17 -O3 main.cpp -o ../bin/MediaBridge.exe -static -static-libgcc -static-libstdc++
```

Using CMake:
```cmd
cd cpp_source
mkdir build && cd build
cmake ..
cmake --build . --config Release
```

## API

- `GET /media` - returns current track info, cover, and waveform
- `GET /media/playpause` - toggle play/pause
- `GET /media/next` - next track
- `GET /media/prev` - previous track
- `GET /media/like` - toggle like on Spotify (sends Alt+Shift+B)
