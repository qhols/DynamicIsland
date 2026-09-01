Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Drawing

$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media, ContentType = WindowsRuntime]

$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' 
}

function AwaitTask($WinRtTask, $ResultType) {
    if ($null -eq $WinRtTask) { return $null }
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    return $netTask.Result
}

$csharpHelper = @'
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Diagnostics;
using System.Threading;

namespace WinRtHelper {
    public static class ThumbnailSaver {
        public static bool SaveStream(object streamObj, string targetJpg, string targetPng) {
            try {
                if (streamObj == null) return false;
                Type extType = null;
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
                    extType = asm.GetType("System.IO.WindowsRuntimeStreamExtensions");
                    if (extType != null) break;
                }
                if (extType == null) return false;
                MethodInfo method = null;
                foreach (var m in extType.GetMethods()) {
                    if (m.Name == "AsStreamForRead" && m.GetParameters().Length == 1) {
                        method = m;
                        break;
                    }
                }
                if (method == null) return false;
                using (var stream = (Stream)method.Invoke(null, new object[] { streamObj }))
                using (var ms = new MemoryStream()) {
                    stream.CopyTo(ms);
                    var bytes = ms.ToArray();
                    File.WriteAllBytes(targetJpg, bytes);
                    try {
                        using (var imgMs = new MemoryStream(bytes))
                        using (var img = Image.FromStream(imgMs)) {
                            img.Save(targetPng, System.Drawing.Imaging.ImageFormat.Png);
                        }
                    } catch {}
                }
                return true;
            } catch {
                return false;
            }
        }

        public static int[] ExtractDominantColor(string imagePath) {
            try {
                if (!File.Exists(imagePath)) return new int[] { 255, 45, 85 };
                using (var bmp = new Bitmap(imagePath)) {
                    long totalR = 0, totalG = 0, totalB = 0;
                    int count = 0;
                    int step = Math.Max(1, bmp.Width / 16);
                    for (int x = 0; x < bmp.Width; x += step) {
                        for (int y = 0; y < bmp.Height; y += step) {
                            var p = bmp.GetPixel(x, y);
                            int brightness = (p.R + p.G + p.B) / 3;
                            int diff = Math.Max(Math.Abs(p.R - p.G), Math.Max(Math.Abs(p.R - p.B), Math.Abs(p.G - p.B)));
                            if (brightness > 25 && brightness < 240 && diff > 15) {
                                totalR += p.R;
                                totalG += p.G;
                                totalB += p.B;
                                count++;
                            }
                        }
                    }
                    if (count > 0) {
                        return new int[] { (int)(totalR / count), (int)(totalG / count), (int)(totalB / count) };
                    }
                    return new int[] { 255, 45, 85 };
                }
            } catch {
                return new int[] { 255, 45, 85 };
            }
        }
    }

    public static class SpotifyController {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr ProcessId);

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const int VK_CONTROL = 0x11;
        private const int VK_MENU = 0x12;
        private const int VK_SHIFT = 0x10;
        private const int VK_B = 0x42;
        private const int VK_S = 0x53;
        private const int VK_R = 0x52;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        private static IntPtr GetSpotifyWindow() {
            var processes = Process.GetProcessesByName("Spotify");
            foreach (var p in processes) {
                if (p.MainWindowHandle != IntPtr.Zero) return p.MainWindowHandle;
            }
            IntPtr hwnd = FindWindow("SpotifyMainWindow", null);
            if (hwnd == IntPtr.Zero) hwnd = FindWindow("Chrome_WidgetWin_0", null);
            return hwnd;
        }

        public static void ToggleLike() {
            IntPtr spotifyHwnd = GetSpotifyWindow();
            IntPtr prevFg = GetForegroundWindow();
            uint curThread = GetCurrentThreadId();
            uint fgThread = GetWindowThreadProcessId(prevFg, IntPtr.Zero);
            uint spThread = spotifyHwnd != IntPtr.Zero ? GetWindowThreadProcessId(spotifyHwnd, IntPtr.Zero) : 0;
            if (spThread != 0) AttachThreadInput(curThread, spThread, true);

            if (spotifyHwnd != IntPtr.Zero) {
                SetForegroundWindow(spotifyHwnd);
                Thread.Sleep(30);
            }
            keybd_event((byte)VK_MENU, 0, 0, UIntPtr.Zero);
            keybd_event((byte)VK_SHIFT, 0, 0, UIntPtr.Zero);
            keybd_event((byte)VK_B, 0, 0, UIntPtr.Zero);
            Thread.Sleep(25);
            keybd_event((byte)VK_B, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            if (prevFg != IntPtr.Zero && prevFg != spotifyHwnd) {
                Thread.Sleep(20);
                SetForegroundWindow(prevFg);
            }
            if (spThread != 0) AttachThreadInput(curThread, spThread, false);
        }

        public static void ToggleShuffle() {
            IntPtr spotifyHwnd = GetSpotifyWindow();
            IntPtr prevFg = GetForegroundWindow();
            uint curThread = GetCurrentThreadId();
            uint fgThread = GetWindowThreadProcessId(prevFg, IntPtr.Zero);
            uint spThread = spotifyHwnd != IntPtr.Zero ? GetWindowThreadProcessId(spotifyHwnd, IntPtr.Zero) : 0;
            if (spThread != 0) AttachThreadInput(curThread, spThread, true);

            if (spotifyHwnd != IntPtr.Zero) {
                SetForegroundWindow(spotifyHwnd);
                Thread.Sleep(30);
            }
            keybd_event((byte)VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event((byte)VK_S, 0, 0, UIntPtr.Zero);
            Thread.Sleep(25);
            keybd_event((byte)VK_S, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            if (prevFg != IntPtr.Zero && prevFg != spotifyHwnd) {
                Thread.Sleep(20);
                SetForegroundWindow(prevFg);
            }
            if (spThread != 0) AttachThreadInput(curThread, spThread, false);
        }

        public static void ToggleRepeat() {
            IntPtr spotifyHwnd = GetSpotifyWindow();
            IntPtr prevFg = GetForegroundWindow();
            uint curThread = GetCurrentThreadId();
            uint fgThread = GetWindowThreadProcessId(prevFg, IntPtr.Zero);
            uint spThread = spotifyHwnd != IntPtr.Zero ? GetWindowThreadProcessId(spotifyHwnd, IntPtr.Zero) : 0;
            if (spThread != 0) AttachThreadInput(curThread, spThread, true);

            if (spotifyHwnd != IntPtr.Zero) {
                SetForegroundWindow(spotifyHwnd);
                Thread.Sleep(30);
            }
            keybd_event((byte)VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event((byte)VK_R, 0, 0, UIntPtr.Zero);
            Thread.Sleep(25);
            keybd_event((byte)VK_R, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event((byte)VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            if (prevFg != IntPtr.Zero && prevFg != spotifyHwnd) {
                Thread.Sleep(20);
                SetForegroundWindow(prevFg);
            }
            if (spThread != 0) AttachThreadInput(curThread, spThread, false);
        }
    }

    [Guid("BCDE0395-E52F-467C-8E3D-C4579291433E")]
    [ComImport]
    class MMDeviceEnumeratorComObject { }

    [Guid("A95664D2-9614-4F35-A746-DE8D563617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig]
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioMeterInformation {
        [PreserveSig]
        int GetPeakValue(out float pfPeak);
        [PreserveSig]
        int GetMeteringChannelCount(out int pnChannelCount);
        [PreserveSig]
        int GetChannelsPeakValues(int u32ChannelCount, [In, Out] float[] afPeakValues);
    }

    public static class Meter {
        private static IAudioMeterInformation _meter;
        private static void Init() {
            if (_meter == null) {
                var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                IMMDevice dev;
                enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
                var iid = typeof(IAudioMeterInformation).GUID;
                object o;
                dev.Activate(ref iid, 1, IntPtr.Zero, out o);
                _meter = (IAudioMeterInformation)o;
            }
        }
        public static float[] GetBars() {
            try {
                Init();
                float peak = 0;
                _meter.GetPeakValue(out peak);
                int count;
                _meter.GetMeteringChannelCount(out count);
                float left = peak, right = peak;
                if (count >= 2) {
                    float[] channels = new float[count];
                    _meter.GetChannelsPeakValues(count, channels);
                    left = channels[0];
                    right = channels[1];
                }
                float mid = (left + right) * 0.5f;
                return new float[] {
                    (float)Math.Round(left * 0.7f + peak * 0.3f, 2),
                    (float)Math.Round(left * 0.35f + mid * 0.65f, 2),
                    (float)Math.Round(peak, 2),
                    (float)Math.Round(right * 0.35f + mid * 0.65f, 2),
                    (float)Math.Round(right * 0.7f + peak * 0.3f, 2)
                };
            } catch { return new float[] { 0f, 0f, 0f, 0f, 0f }; }
        }
    }
}
'@

try { Add-Type -TypeDefinition $csharpHelper -Language CSharp -ReferencedAssemblies "System.Drawing" } catch {}

$tempDir = [System.IO.Path]::GetTempPath()
$global:coverJpg = Join-Path $tempDir "dynamic_island_cover.jpg"
$global:coverPng = Join-Path $tempDir "dynamic_island_cover.png"
$global:lastSavedTrack = ""
$global:coverVersion = 0
$global:coverBase64 = ""
$global:coverColor = @(255, 45, 85)

function Find-BestSession($mgr) {
    $sessions = $mgr.GetSessions()
    if ($null -eq $sessions -or $sessions.Count -eq 0) {
        return $mgr.GetCurrentSession()
    }
    
    $playingMusicSession = $null
    $playingAnySession = $null
    $musicSession = $null
    
    foreach ($s in $sessions) {
        $appId = if ($s.SourceAppId) { $s.SourceAppId.ToLower() } else { "" }
        $isMusicApp = ($appId -match "spotify" -or $appId -match "yandex" -or $appId -match "applemusic" -or $appId -match "music" -or $appId -match "aimp" -or $appId -match "foobar")
        $playback = $s.GetPlaybackInfo()
        $isPlaying = ($playback -and $playback.PlaybackStatus -eq [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing)
        
        if ($isPlaying -and $isMusicApp) {
            return $s
        }
        if ($isPlaying -and $null -eq $playingAnySession) {
            $playingAnySession = $s
        }
        if ($isMusicApp -and $null -eq $musicSession) {
            $musicSession = $s
        }
    }
    
    if ($playingAnySession) { return $playingAnySession }
    if ($musicSession) { return $musicSession }
    return $sessions[0]
}

function Get-MediaInfo {
    try {
        $mgrTask = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $mgr = AwaitTask $mgrTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
        if ($null -eq $mgr) { return $null }

        $session = Find-BestSession $mgr
        if ($null -eq $session) { return $null }

        $propsTask = $session.TryGetMediaPropertiesAsync()
        $props = AwaitTask $propsTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        if ($null -eq $props) { return $null }

        $playback = $session.GetPlaybackInfo()
        $timeline = $session.GetTimelineProperties()

        $isPlaying = if ($playback) { 
            $playback.PlaybackStatus -eq [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing 
        } else { $false }

        $isShuffle = if ($playback) { $playback.IsShuffleActive } else { $false }
        $repeatMode = 0
        if ($playback -and $playback.AutoRepeatMode) {
            $repStr = $playback.AutoRepeatMode.ToString()
            if ($repStr -eq "List") { $repeatMode = 1 }
            elseif ($repStr -eq "Track") { $repeatMode = 2 }
        }

        $pos = if ($timeline) { [int]$timeline.Position.TotalSeconds } else { 0 }
        $dur = if ($timeline) { [int]$timeline.EndTime.TotalSeconds } else { 0 }

        $title = if ($props.Title) { $props.Title.Trim() } else { "" }
        $artist = if ($props.Artist) { $props.Artist.Trim() } else { "" }
        $album = if ($props.AlbumTitle) { $props.AlbumTitle.Trim() } else { "" }
        $trackKey = "$artist - $title"

        if ($trackKey -ne $global:lastSavedTrack -and $title -ne "") {
            $global:lastSavedTrack = $trackKey
            $global:coverVersion++
            $global:coverBase64 = ""
            $saved = $false

            if ($props.Thumbnail) {
                try {
                    $streamTask = $props.Thumbnail.OpenReadAsync()
                    $stream = AwaitTask $streamTask ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                    if ($stream) {
                        $saved = [WinRtHelper.ThumbnailSaver]::SaveStream($stream, $global:coverJpg, $global:coverPng)
                    }
                } catch {}
            }

            if (-not $saved) {
                try {
                    $q = [System.Web.HttpUtility]::UrlEncode($trackKey)
                    $itunesUrl = "https://itunes.apple.com/search?term=$q&limit=1&entity=song"
                    $jsonRes = Invoke-RestMethod -Uri $itunesUrl -TimeoutSec 3 -ErrorAction SilentlyContinue
                    if ($jsonRes -and $jsonRes.resultCount -gt 0 -and $jsonRes.results[0].artworkUrl100) {
                        $artUrl = $jsonRes.results[0].artworkUrl100 -replace "100x100bb.jpg", "600x600bb.jpg"
                        Invoke-WebRequest -Uri $artUrl -OutFile $global:coverJpg -TimeoutSec 4 -ErrorAction SilentlyContinue
                        Copy-Item $global:coverJpg $global:coverPng -Force -ErrorAction SilentlyContinue
                        $saved = $true
                    }
                } catch {}
            }

            if (Test-Path $global:coverJpg) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($global:coverJpg)
                    $global:coverBase64 = [Convert]::ToBase64String($bytes)
                    $global:coverColor = [WinRtHelper.ThumbnailSaver]::ExtractDominantColor($global:coverJpg)
                } catch {}
            }
        }

        $appId = $session.SourceAppId
        $hasCover = ($global:coverBase64 -ne "") -or (Test-Path $global:coverPng)
        $bars = [WinRtHelper.Meter]::GetBars()

        $cleanPath = $global:coverPng.Replace('\', '/')
        $cleanJpg = $global:coverJpg.Replace('\', '/')

        return @{
            is_playing   = $isPlaying
            title        = $title
            artist       = $artist
            album        = $album
            app          = $appId
            position     = $pos
            duration     = $dur
            cover_path   = $cleanPath
            cover_jpg    = $cleanJpg
            cover_base64 = $global:coverBase64
            cover_ver    = $global:coverVersion
            has_cover    = $hasCover
            cover_color  = $global:coverColor
            waveform     = $bars
            shuffle      = $isShuffle
            repeat       = $repeatMode
        }
    } catch {
        return $null
    }
}

function Handle-MediaCommand($cmd) {
    try {
        $mgrTask = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $mgr = AwaitTask $mgrTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
        $session = if ($mgr) { Find-BestSession $mgr } else { $null }

        if ($cmd -eq "playpause") {
            if ($session) { $session.TryTogglePlayPauseAsync() | Out-Null }
        } elseif ($cmd -eq "next") {
            if ($session) { $session.TrySkipNextAsync() | Out-Null }
        } elseif ($cmd -eq "prev") {
            if ($session) { $session.TrySkipPreviousAsync() | Out-Null }
        } elseif ($cmd -eq "shuffle") {
            [WinRtHelper.SpotifyController]::ToggleShuffle()
            if ($session) {
                try {
                    $pb = $session.GetPlaybackInfo()
                    $cur = if ($pb) { $pb.IsShuffleActive } else { $false }
                    $session.TryChangeShuffleActiveAsync(-not $cur) | Out-Null
                } catch {}
            }
        } elseif ($cmd -eq "repeat") {
            [WinRtHelper.SpotifyController]::ToggleRepeat()
            if ($session) {
                try {
                    $pb = $session.GetPlaybackInfo()
                    $curRep = if ($pb) { $pb.AutoRepeatMode.ToString() } else { "None" }
                    $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::None
                    if ($curRep -eq "None") { $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::List }
                    elseif ($curRep -eq "List") { $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::Track }
                    $session.TryChangeAutoRepeatModeAsync($nextRep) | Out-Null
                } catch {}
            }
        } elseif ($cmd -eq "like") {
            [WinRtHelper.SpotifyController]::ToggleLike()
        }
    } catch {}
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:45455/")
try {
    $listener.Start()
} catch {
    Exit
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $path = $request.Url.LocalPath.ToLower()

        if ($path -eq "/media") {
            $data = Get-MediaInfo
            if ($null -eq $data) {
                $bars = [WinRtHelper.Meter]::GetBars()
                $data = @{
                    is_playing   = $false
                    title        = ""
                    artist       = ""
                    album        = ""
                    app          = ""
                    position     = 0
                    duration     = 0
                    cover_path   = ""
                    cover_jpg    = ""
                    cover_base64 = ""
                    cover_ver    = 0
                    has_cover    = $false
                    cover_color  = @(255, 45, 85)
                    waveform     = $bars
                    shuffle      = $false
                    repeat       = 0
                }
            }
            $json = $data | ConvertTo-Json -Compress -Depth 3
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } elseif ($path -match "^/media/(playpause|next|prev|shuffle|repeat|like)$") {
            $cmd = $matches[1]
            Handle-MediaCommand $cmd
            $json = '{"status":"ok"}'
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        $response.Close()
    } catch {}
}