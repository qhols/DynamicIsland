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
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        const int VK_MENU = 0x12;
        const int VK_SHIFT = 0x10;
        const int VK_B = 0x42;
        const uint KEYEVENTF_KEYUP = 0x0002;

        public static bool LikeTrack() {
            try {
                var processes = Process.GetProcessesByName("Spotify");
                IntPtr spotifyHwnd = IntPtr.Zero;
                foreach (var p in processes) {
                    if (p.MainWindowHandle != IntPtr.Zero) {
                        spotifyHwnd = p.MainWindowHandle;
                        break;
                    }
                }
                if (spotifyHwnd == IntPtr.Zero) {
                    spotifyHwnd = FindWindow("SpotifyMainWindow", null);
                }
                if (spotifyHwnd == IntPtr.Zero) {
                    spotifyHwnd = FindWindow("Chrome_WidgetWin_0", null);
                }

                IntPtr prevFg = GetForegroundWindow();
                if (spotifyHwnd != IntPtr.Zero) {
                    SetForegroundWindow(spotifyHwnd);
                    Thread.Sleep(35);
                }

                keybd_event((byte)VK_MENU, 0, 0, UIntPtr.Zero);
                keybd_event((byte)VK_SHIFT, 0, 0, UIntPtr.Zero);
                keybd_event((byte)VK_B, 0, 0, UIntPtr.Zero);
                Thread.Sleep(25);
                keybd_event((byte)VK_B, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                keybd_event((byte)VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                keybd_event((byte)VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

                if (prevFg != IntPtr.Zero && prevFg != spotifyHwnd) {
                    Thread.Sleep(25);
                    SetForegroundWindow(prevFg);
                }
                return true;
            } catch {
                return false;
            }
        }
    }
}

namespace AudioMeter {
    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291433E")]
    public class MMDeviceEnumeratorComObject { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int NotImpl1();
        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
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

$global:coverJpg = Join-Path $PSScriptRoot "cover.jpg"
$global:coverPng = Join-Path $PSScriptRoot "cover.png"
$global:umbJpg = "C:\Umbrella\scripts\cover.jpg"
$global:umbPng = "C:\Umbrella\scripts\cover.png"
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
    
    if ($null -ne $playingAnySession) { return $playingAnySession }
    if ($null -ne $musicSession) { return $musicSession }
    return $mgr.GetCurrentSession()
}

function Fetch-OnlineArtwork($query) {
    try {
        $term = [System.Web.HttpUtility]::UrlEncode($query)
        $url = "https://itunes.apple.com/search?term=$term&limit=1&entity=song"
        $res = Invoke-RestMethod -Uri $url -TimeoutSec 2
        if ($res -and $res.results -and $res.results.Count -gt 0) {
            $artUrl = $res.results[0].artworkUrl100
            if ($artUrl) {
                $artUrl600 = $artUrl.Replace("100x100bb.jpg", "600x600bb.jpg")
                Invoke-WebRequest -Uri $artUrl600 -OutFile $global:coverJpg -TimeoutSec 3
                if (Test-Path $global:coverJpg) {
                    $img = [System.Drawing.Image]::FromFile($global:coverJpg)
                    $img.Save($global:coverPng, [System.Drawing.Imaging.ImageFormat]::Png)
                    $img.Dispose()
                    return $true
                }
            }
        }
    } catch {}
    return $false
}

function Get-MediaInfo {
    try {
        $mgr = AwaitTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
        if ($null -eq $mgr) { return @{ is_playing = $false } }
        
        $session = Find-BestSession $mgr
        if ($null -eq $session) { return @{ is_playing = $false } }
        
        $props = AwaitTask ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        $playback = $session.GetPlaybackInfo()
        $timeline = $session.GetTimelineProperties()
        
        $isPlaying = ($playback.PlaybackStatus -eq [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing)
        
        $pos = 0
        $dur = 0
        if ($null -ne $timeline) {
            $pos = [math]::Round($timeline.Position.TotalSeconds)
            $dur = [math]::Round($timeline.EndTime.TotalSeconds)
        }
        
        $title = if ($props -and $props.Title) { $props.Title } else { "" }
        $artist = if ($props -and $props.Artist) { $props.Artist } else { "" }
        $album = if ($props -and $props.AlbumTitle) { $props.AlbumTitle } else { "" }
        
        $currentTrackKey = "$title|$artist|$album"
        
        if ($currentTrackKey -ne $global:lastSavedTrack -and $title -ne "") {
            $saved = $false
            if ($props.Thumbnail) {
                try {
                    $stream = AwaitTask ($props.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                    if ($stream) {
                        $saved = [WinRtHelper.ThumbnailSaver]::SaveStream($stream, $global:coverJpg, $global:coverPng)
                    }
                } catch {}
            }
            if (-not $saved) {
                $saved = Fetch-OnlineArtwork "$artist $title"
            }
            
            if ($saved) {
                try { [System.IO.File]::Copy($global:coverJpg, $global:umbJpg, $true) } catch {}
                try { [System.IO.File]::Copy($global:coverPng, $global:umbPng, $true) } catch {}
                
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($global:coverPng)
                    $global:coverBase64 = [Convert]::ToBase64String($bytes)
                } catch {
                    $global:coverBase64 = ""
                }
                
                try {
                    $global:coverColor = [WinRtHelper.ThumbnailSaver]::ExtractDominantColor($global:coverPng)
                } catch {
                    $global:coverColor = @(255, 45, 85)
                }
                
                $global:lastSavedTrack = $currentTrackKey
                $global:coverVersion++
            }
        }
        
        $hasCover = [System.IO.File]::Exists($global:coverPng) -or [System.IO.File]::Exists($global:coverJpg)
        $audioBars = [AudioMeter.Meter]::GetBars()
        
        return @{
            is_playing = $isPlaying
            title = $title
            artist = $artist
            album = $album
            position = $pos
            duration = $dur
            app = $session.SourceAppId
            cover_path = $global:coverPng.Replace("\", "/")
            cover_jpg = $global:coverJpg.Replace("\", "/")
            cover_base64 = $global:coverBase64
            cover_ver = $global:coverVersion
            cover_color = $global:coverColor
            has_cover = $hasCover
            waveform = $audioBars
        }
    } catch {
        return @{ is_playing = $false; error = $_.ToString() }
    }
}

function Control-Media($action) {
    try {
        $mgr = AwaitTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
        if ($null -eq $mgr) { return $false }
        $session = Find-BestSession $mgr
        if ($null -eq $session) { return $false }
        
        switch ($action) {
            "playpause" {
                $task = $session.TryTogglePlayPauseAsync()
                $null = AwaitTask $task ([System.Boolean])
            }
            "next" {
                $task = $session.TrySkipNextAsync()
                $null = AwaitTask $task ([System.Boolean])
            }
            "prev" {
                $task = $session.TrySkipPreviousAsync()
                $null = AwaitTask $task ([System.Boolean])
            }
            "like" {
                $null = [WinRtHelper.SpotifyController]::LikeTrack()
            }
        }
        return $true
    } catch {
        return $false
    }
}

$port = 45455
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()
Write-Host "Media Bridge running on http://127.0.0.1:$port/"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }
        
        $path = $request.Url.AbsolutePath.ToLower()
        $jsonResult = ""
        
        if ($path -eq "/media/playpause") {
            $null = Control-Media "playpause"
            $jsonResult = '{"status":"ok"}'
        } elseif ($path -eq "/media/next") {
            $null = Control-Media "next"
            $jsonResult = '{"status":"ok"}'
        } elseif ($path -eq "/media/prev") {
            $null = Control-Media "prev"
            $jsonResult = '{"status":"ok"}'
        } elseif ($path -eq "/media/like") {
            $null = Control-Media "like"
            $jsonResult = '{"status":"ok"}'
        } else {
            $data = Get-MediaInfo
            $jsonResult = $data | ConvertTo-Json -Compress
        }
        
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResult)
        $response.ContentType = "application/json; charset=utf-8"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
} finally {
    $listener.Stop()
}
