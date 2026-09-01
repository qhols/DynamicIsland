@echo off
echo Building MediaBridge C++ Server...
g++ -std=c++17 -O3 -mwindows main.cpp -o ..\bin\MediaBridge.exe -lws2_32 -lole32 -lwininet -lgdiplus
if %ERRORLEVEL% equ 0 (
    echo Build SUCCESS! Output: ..\bin\MediaBridge.exe
) else (
    echo Build FAILED!
)
pause
