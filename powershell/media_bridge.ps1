# Dynamic Island Media Engine UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.MediaPlaybackAutoRepeatMode, Windows.Media, ContentType = WindowsRuntime]

$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' 
}

function AwaitTask($WinRtTask, $ResultType, $TimeoutMs = 200) {
    if ($null -eq $WinRtTask) { return $null }
    try {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        if (-not $netTask.Wait($TimeoutMs)) { return $null }
        return $netTask.Result
    } catch {
        return $null
    }
}

$csharpHelper = @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Diagnostics;
using System.Threading;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

namespace WinRtHelper {
    public static class ThumbnailSaver {
        public static bool SaveStream(object streamObj, string targetJpg, string targetPng, string umbJpg, string umbPng) {
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
                    if (!string.IsNullOrEmpty(umbJpg)) {
                        File.WriteAllBytes(umbJpg, bytes);
                        try {
                            string staticJpg = Path.Combine(Path.GetDirectoryName(umbJpg), "dynamic_island_cover.jpg");
                            File.WriteAllBytes(staticJpg, bytes);
                        } catch {}
                    }
                    try {
                        using (var imgMs = new MemoryStream(bytes))
                        using (var img = Image.FromStream(imgMs)) {
                            img.Save(targetPng, System.Drawing.Imaging.ImageFormat.Png);
                            if (!string.IsNullOrEmpty(umbPng)) {
                                img.Save(umbPng, System.Drawing.Imaging.ImageFormat.Png);
                                try {
                                    string staticPng = Path.Combine(Path.GetDirectoryName(umbPng), "dynamic_island_cover.png");
                                    img.Save(staticPng, System.Drawing.Imaging.ImageFormat.Png);
                                } catch {}
                            }
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

    public static class SpotifyCdp {
        public static bool? ToggleLike() {
            try {
                var req = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:9222/json");
                req.Timeout = 300;
                string json;
                using (var resp = req.GetResponse())
                using (var sr = new StreamReader(resp.GetResponseStream())) {
                    json = sr.ReadToEnd();
                }

                var match = Regex.Match(json, "\"webSocketDebuggerUrl\"\\s*:\\s*\"(ws://127\\.0\\.0\\.1:9222/devtools/page/[a-zA-Z0-9]+)\"");
                if (!match.Success) return null;
                string wsUrl = match.Groups[1].Value;
                var uri = new Uri(wsUrl);

                using (var tcp = new TcpClient("127.0.0.1", 9222))
                using (var stream = tcp.GetStream()) {
                    stream.ReadTimeout = 500;
                    string key = Convert.ToBase64String(Guid.NewGuid().ToByteArray());
                    string handshake = "GET " + uri.PathAndQuery + " HTTP/1.1\r\n" +
                                       "Host: 127.0.0.1:9222\r\n" +
                                       "Upgrade: websocket\r\n" +
                                       "Connection: Upgrade\r\n" +
                                       "Sec-WebSocket-Key: " + key + "\r\n" +
                                       "Sec-WebSocket-Version: 13\r\n\r\n";
                    byte[] hsBytes = Encoding.ASCII.GetBytes(handshake);
                    stream.Write(hsBytes, 0, hsBytes.Length);

                    byte[] buf = new byte[2048];
                    stream.Read(buf, 0, buf.Length);

                    string js = "(async () => {" +
                                "  try {" +
                                "    if (window.Spicetify && window.Spicetify.Platform && window.Spicetify.Platform.LibraryAPI) {" +
                                "      const item = Spicetify.Player.data.item;" +
                                "      if (!item || !item.uri) return 'NO_ITEM';" +
                                "      const uri = item.uri;" +
                                "      const lib = Spicetify.Platform.LibraryAPI;" +
                                "      const res = await lib.contains(uri);" +
                                "      const isLiked = Array.isArray(res) ? res[0] : res;" +
                                "      if (isLiked) {" +
                                "        await lib.remove({ uris: [uri] });" +
                                "        Spicetify.showNotification('Удалено из Любимых треков');" +
                                "        return 'REMOVED';" +
                                "      } else {" +
                                "        await lib.add({ uris: [uri] });" +
                                "        Spicetify.showNotification('Добавлено в Любимые треки');" +
                                "        return 'ADDED';" +
                                "      }" +
                                "    }" +
                                "    return 'NO_SPICETIFY';" +
                                "  } catch { return 'ERR'; }" +
                                "})()";

                    string payload = "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":\"" + js + "\",\"awaitPromise\":true,\"returnByValue\":true}}";
                    byte[] plBytes = Encoding.UTF8.GetBytes(payload);

                    var frame = new MemoryStream();
                    frame.WriteByte(0x81);
                    if (plBytes.Length <= 125) {
                        frame.WriteByte((byte)(0x80 | plBytes.Length));
                    } else {
                        frame.WriteByte(0x80 | 126);
                        frame.WriteByte((byte)(plBytes.Length >> 8));
                        frame.WriteByte((byte)(plBytes.Length & 0xFF));
                    }

                    byte[] mask = new byte[] { 0x12, 0x34, 0x56, 0x78 };
                    frame.Write(mask, 0, 4);
                    for (int i = 0; i < plBytes.Length; i++) frame.WriteByte((byte)(plBytes[i] ^ mask[i % 4]));
                    byte[] frameBytes = frame.ToArray();
                    stream.Write(frameBytes, 0, frameBytes.Length);

                    byte[] resBuf = new byte[8192];
                    int total = 0;
                    while (total < resBuf.Length) {
                        int read = stream.Read(resBuf, total, resBuf.Length - total);
                        if (read <= 0) break;
                        total += read;
                        string cur = Encoding.UTF8.GetString(resBuf, 0, total);
                        if (cur.IndexOf("ADDED") >= 0) return true;
                        if (cur.IndexOf("REMOVED") >= 0) return false;
                        if (cur.IndexOf("\"result\":") >= 0 && cur.IndexOf("}") >= 0) break;
                    }
                    return null;
                }
            } catch {
                return null;
            }
        }
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int NotImpl1();
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
    }

    
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionManager2 {
        [PreserveSig] int NotImpl1();
        [PreserveSig] int NotImpl2();
        [PreserveSig] int GetSessionEnumerator(out IntPtr SessionEnum);
    }

    public static class AppAudioControl {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetThreadDesktop(IntPtr hDesktop);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        private static volatile bool _isDotaFocused = false;
        private static Thread _watcherThread;
        private static bool _started = false;
        private static readonly object _lock = new object();

        public static void StartFocusWatcher() {
            lock (_lock) {
                if (_started) return;
                _started = true;
                _watcherThread = new Thread(FocusLoop) {
                    IsBackground = true,
                    Name = "DotaFocusWatcher"
                };
                _watcherThread.SetApartmentState(ApartmentState.STA);
                _watcherThread.Start();
            }
        }

        private static void FocusLoop() {
            try {
                IntPtr hDesk = OpenDesktop("default", 0, false, 0x01FF);
                if (hDesk != IntPtr.Zero) {
                    SetThreadDesktop(hDesk);
                }
            } catch {}

            while (true) {
                try {
                    IntPtr fg = GetForegroundWindow();
                    if (fg != IntPtr.Zero) {
                        uint pid = 0;
                        GetWindowThreadProcessId(fg, out pid);
                        if (pid > 0) {
                            var p = Process.GetProcessById((int)pid);
                            _isDotaFocused = (p != null && p.ProcessName.IndexOf("dota2", StringComparison.OrdinalIgnoreCase) >= 0);
                        } else {
                            _isDotaFocused = false;
                        }
                    } else {
                        _isDotaFocused = false;
                    }
                } catch {
                    _isDotaFocused = false;
                }
                Thread.Sleep(100);
            }
        }

        public static bool IsDotaFocused() {
            StartFocusWatcher();
            return _isDotaFocused;
        }

        [DllImport("ole32.dll")]
        private static extern int CoInitializeEx(IntPtr pvReserved, uint dwCoInit);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetCountDelegate(IntPtr thisPtr, out int count);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetSessionDelegate(IntPtr thisPtr, int index, out IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceDelegate(IntPtr thisPtr, ref Guid riid, out IntPtr ppv);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetProcessIdDelegate(IntPtr thisPtr, out uint pid);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetMasterVolumeDelegate(IntPtr thisPtr, out float level);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int SetMasterVolumeDelegate(IntPtr thisPtr, float level, ref Guid eventContext);

        private static Guid IID_IAudioSessionControl2 = new Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D");
        private static Guid IID_ISimpleAudioVolume = new Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8");

        private static bool IsTargetApp(string name) {
            if (string.IsNullOrEmpty(name)) return false;
            return name.Contains("dotify") || name.Contains("spotify") || name.Contains("music") ||
                   name.Contains("msedge") || name.Contains("chrome") || name.Contains("firefox") ||
                   name.Contains("yandex") || name.Contains("opera") || name.Contains("browser");
        }

        public static float GetAppVolume() {
            CoInitializeEx(IntPtr.Zero, 0);
            float foundVol = -1.0f;
            try {
                var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                IMMDevice dev;
                if (enumerator.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return 1.0f;
                Guid IID_IAudioSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
                object o;
                if (dev.Activate(ref IID_IAudioSessionManager2, 1, IntPtr.Zero, out o) != 0 || o == null) return 1.0f;
                var mgr = (IAudioSessionManager2)o;
                IntPtr pEnum;
                if (mgr.GetSessionEnumerator(out pEnum) != 0 || pEnum == IntPtr.Zero) return 1.0f;

                IntPtr vtbl = Marshal.ReadIntPtr(pEnum);
                var getCount = (GetCountDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 3 * IntPtr.Size), typeof(GetCountDelegate));
                var getSession = (GetSessionDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 4 * IntPtr.Size), typeof(GetSessionDelegate));
                int count = 0;
                getCount(pEnum, out count);

                for (int i = 0; i < count; i++) {
                    IntPtr pSession;
                    getSession(pEnum, i, out pSession);
                    if (pSession == IntPtr.Zero) continue;

                    IntPtr sVtbl = Marshal.ReadIntPtr(pSession);
                    var qi = (QueryInterfaceDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(sVtbl, 0), typeof(QueryInterfaceDelegate));

                    uint pid = 0;
                    IntPtr pCtl2;
                    if (qi(pSession, ref IID_IAudioSessionControl2, out pCtl2) == 0 && pCtl2 != IntPtr.Zero) {
                        IntPtr ctl2Vtbl = Marshal.ReadIntPtr(pCtl2);
                        var getPid = (GetProcessIdDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(ctl2Vtbl, 14 * IntPtr.Size), typeof(GetProcessIdDelegate));
                        getPid(pCtl2, out pid);
                        Marshal.Release(pCtl2);
                    }

                    string name = "";
                    try { if (pid > 0) name = Process.GetProcessById((int)pid).ProcessName.ToLower(); } catch {}

                    if (IsTargetApp(name)) {
                        IntPtr pVol;
                        if (qi(pSession, ref IID_ISimpleAudioVolume, out pVol) == 0 && pVol != IntPtr.Zero) {
                            IntPtr volVtbl = Marshal.ReadIntPtr(pVol);
                            var getVol = (GetMasterVolumeDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(volVtbl, 4 * IntPtr.Size), typeof(GetMasterVolumeDelegate));
                            float cur = 1.0f;
                            getVol(pVol, out cur);
                            foundVol = cur;
                            Marshal.Release(pVol);
                            Marshal.Release(pSession);
                            break;
                        }
                    }
                    Marshal.Release(pSession);
                }
                Marshal.Release(pEnum);
            } catch {}
            return foundVol >= 0.0f ? foundVol : 1.0f;
        }

        public static float StepAppVolume(float delta) {
            CoInitializeEx(IntPtr.Zero, 0);
            float lastNewVol = -1.0f;
            try {
                var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                IMMDevice dev;
                if (enumerator.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return 1.0f;
                Guid IID_IAudioSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
                object o;
                if (dev.Activate(ref IID_IAudioSessionManager2, 1, IntPtr.Zero, out o) != 0 || o == null) return 1.0f;
                var mgr = (IAudioSessionManager2)o;
                IntPtr pEnum;
                if (mgr.GetSessionEnumerator(out pEnum) != 0 || pEnum == IntPtr.Zero) return 1.0f;

                IntPtr vtbl = Marshal.ReadIntPtr(pEnum);
                var getCount = (GetCountDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 3 * IntPtr.Size), typeof(GetCountDelegate));
                var getSession = (GetSessionDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 4 * IntPtr.Size), typeof(GetSessionDelegate));
                int count = 0;
                getCount(pEnum, out count);

                for (int i = 0; i < count; i++) {
                    IntPtr pSession;
                    getSession(pEnum, i, out pSession);
                    if (pSession == IntPtr.Zero) continue;

                    IntPtr sVtbl = Marshal.ReadIntPtr(pSession);
                    var qi = (QueryInterfaceDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(sVtbl, 0), typeof(QueryInterfaceDelegate));

                    uint pid = 0;
                    IntPtr pCtl2;
                    if (qi(pSession, ref IID_IAudioSessionControl2, out pCtl2) == 0 && pCtl2 != IntPtr.Zero) {
                        IntPtr ctl2Vtbl = Marshal.ReadIntPtr(pCtl2);
                        var getPid = (GetProcessIdDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(ctl2Vtbl, 14 * IntPtr.Size), typeof(GetProcessIdDelegate));
                        getPid(pCtl2, out pid);
                        Marshal.Release(pCtl2);
                    }

                    string name = "";
                    try { if (pid > 0) name = Process.GetProcessById((int)pid).ProcessName.ToLower(); } catch {}

                    if (IsTargetApp(name)) {
                        IntPtr pVol;
                        if (qi(pSession, ref IID_ISimpleAudioVolume, out pVol) == 0 && pVol != IntPtr.Zero) {
                            IntPtr volVtbl = Marshal.ReadIntPtr(pVol);
                            var getVol = (GetMasterVolumeDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(volVtbl, 4 * IntPtr.Size), typeof(GetMasterVolumeDelegate));
                            var setVol = (SetMasterVolumeDelegate)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(volVtbl, 3 * IntPtr.Size), typeof(SetMasterVolumeDelegate));
                            float cur = 1.0f;
                            getVol(pVol, out cur);
                            float newVol = Math.Min(1.0f, Math.Max(0.0f, cur + delta));
                            Guid g = Guid.Empty;
                            setVol(pVol, newVol, ref g);
                            lastNewVol = newVol;
                            Marshal.Release(pVol);
                        }
                    }
                    Marshal.Release(pSession);
                }
                Marshal.Release(pEnum);
            } catch {}
            return lastNewVol >= 0.0f ? lastNewVol : 1.0f;
        }
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
                if (_meter == null) return new float[] { 0f, 0f, 0f, 0f, 0f };
                float peak = 0;
                _meter.GetPeakValue(out peak);
                if (peak <= 0.001f) return new float[] { 0f, 0f, 0f, 0f, 0f };
                float p = Math.Min(1.0f, Math.Max(0.0f, peak));
                return new float[] {
                    (float)Math.Round(p * 0.7f, 2),
                    (float)Math.Round(p * 0.85f, 2),
                    (float)Math.Round(p, 2),
                    (float)Math.Round(p * 0.85f, 2),
                    (float)Math.Round(p * 0.7f, 2)
                };
            } catch { return new float[] { 0f, 0f, 0f, 0f, 0f }; }
        }
    }
}
'@

try { Add-Type -TypeDefinition $csharpHelper -Language CSharp -ReferencedAssemblies "System.Drawing" } catch {}

$global:tempDir = [System.IO.Path]::GetTempPath()
$global:coverJpg = ""
$global:coverPng = ""
$global:lastSavedTrack = ""
$global:coverVersion = 0
$global:coverBase64 = ""
$global:coverColor = @(255, 45, 85)
$global:lastValidData = $null
$global:currentIsLiked = $false

function Find-BestSession($mgr) {
    if ($null -eq $mgr) { return $null }
    
    $sessions = $mgr.GetSessions()
    if ($null -eq $sessions -or $sessions.Count -eq 0) {
        return $mgr.GetCurrentSession()
    }
    
    $musicPlaying = $null
    $musicPaused = $null
    $anyPlaying = $null
    
    foreach ($s in $sessions) {
        $appId = if ($s.SourceAppId) { $s.SourceAppId.ToLower() } else { "" }
        $pb = $s.GetPlaybackInfo()
        $isPlaying = ($pb -and $pb.PlaybackStatus.ToString() -eq "Playing")
        $hasMusicControls = ($pb -and ($pb.Controls.IsShuffleEnabled -or $pb.Controls.IsRepeatEnabled))
        $isMusicApp = ($appId -match "spotify" -or $appId -match "yandex" -or $appId -match "applemusic" -or $appId -match "music" -or $appId -match "aimp" -or $appId -match "foobar" -or $hasMusicControls)
        
        if ($isPlaying -and $isMusicApp) {
            return $s
        }
        if ($isMusicApp -and $null -eq $musicPaused) {
            $musicPaused = $s
        }
        if ($isPlaying -and $null -eq $anyPlaying) {
            $anyPlaying = $s
        }
    }
    
    if ($musicPaused) { return $musicPaused }
    if ($anyPlaying) { return $anyPlaying }
    
    $cur = $mgr.GetCurrentSession()
    if ($cur) { return $cur }
    return $sessions[0]
}

function Fetch-Cover($props, $trackKey, $title, $artist) {
    $global:coverVersion++
    $ver = $global:coverVersion
    $targetJpg = Join-Path $global:tempDir "dynamic_island_cover_$($ver).jpg"
    $targetPng = Join-Path $global:tempDir "dynamic_island_cover_$($ver).png"
    
    $umbDir = "C:\Umbrella\scripts"
    $umbJpg = if (Test-Path $umbDir) { Join-Path $umbDir "dynamic_island_cover_$($ver).jpg" } else { "" }
    $umbPng = if (Test-Path $umbDir) { Join-Path $umbDir "dynamic_island_cover_$($ver).png" } else { "" }

    $saved = $false

    if ($props -and $props.Thumbnail) {
        try {
            $streamTask = $props.Thumbnail.OpenReadAsync()
            $stream = AwaitTask $streamTask ([Windows.Storage.Streams.IRandomAccessStreamWithContentType]) 300
            if ($stream) {
                $saved = [WinRtHelper.ThumbnailSaver]::SaveStream($stream, $targetJpg, $targetPng, $umbJpg, $umbPng)
            }
        } catch {}
    }

    if ($saved -and (Test-Path $targetJpg)) {
        try {
            if ($ver -gt 2) {
                $prevVer = $ver - 2
                if (Test-Path $umbDir) {
                    Remove-Item (Join-Path $umbDir "dynamic_island_cover_$($prevVer).*") -Force -ErrorAction SilentlyContinue
                }
                Remove-Item (Join-Path $global:tempDir "dynamic_island_cover_$($prevVer).*") -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $targetPng) {
                $bytes = [System.IO.File]::ReadAllBytes($targetPng)
            } else {
                $bytes = [System.IO.File]::ReadAllBytes($targetJpg)
            }
            $global:coverBase64 = [Convert]::ToBase64String($bytes)
            $global:coverColor = [WinRtHelper.ThumbnailSaver]::ExtractDominantColor($targetJpg)
            $global:coverJpg = $targetJpg
            $global:coverPng = $targetPng
        } catch {
            $global:coverBase64 = ""
            $global:coverJpg = ""
            $global:coverPng = ""
        }
    } else {
        $global:coverBase64 = ""
        $global:coverJpg = ""
        $global:coverPng = ""
    }
}

function Get-MediaInfo {
    try {
        $mgrTask = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $mgr = AwaitTask $mgrTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]) 150
        if ($null -eq $mgr) { return $global:lastValidData }

        $session = Find-BestSession $mgr
        if ($null -eq $session) { return $global:lastValidData }

        $propsTask = $session.TryGetMediaPropertiesAsync()
        $props = AwaitTask $propsTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]) 100
        if ($null -eq $props) { return $global:lastValidData }

        $playback = $session.GetPlaybackInfo()
        $timeline = $session.GetTimelineProperties()

        $isPlaying = if ($playback) { 
            $playback.PlaybackStatus.ToString() -eq "Playing" 
        } else { $false }

        $isShuffle = if ($playback) { [bool]$playback.IsShuffleActive } else { $false }
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

        $needsCover = ($trackKey -ne $global:lastSavedTrack) -or ($global:coverJpg -eq "" -or -not (Test-Path $global:coverJpg))
        if ($needsCover -and $title -ne "") {
            $global:lastSavedTrack = $trackKey
            Fetch-Cover $props $trackKey $title $artist
        }

        $appId = if ($session.SourceAppId) { $session.SourceAppId } else { "" }
        $hasCover = ($global:coverBase64 -ne "") -or ($global:coverPng -ne "" -and (Test-Path $global:coverPng))
        $bars = [WinRtHelper.Meter]::GetBars()
        $appVol = [WinRtHelper.AppAudioControl]::GetAppVolume()
        $volInt = [int][Math]::Round($appVol * 100)

        $cleanPath = $global:coverPng.Replace('\', '/')
        $cleanJpg = $global:coverJpg.Replace('\', '/')

        $res = @{
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
            volume       = $volInt
            shuffle      = $isShuffle
            repeat       = $repeatMode
            is_liked     = $global:currentIsLiked
        }

        if ($title -ne "") {
            $global:lastValidData = $res
        }
        return $res
    } catch {
        return $global:lastValidData
    }
}

function Handle-MediaCommand($cmd) {
    try {
        if ($cmd -eq "volup") {
            [WinRtHelper.AppAudioControl]::StepAppVolume(0.04) | Out-Null
            return
        } elseif ($cmd -eq "voldown") {
            [WinRtHelper.AppAudioControl]::StepAppVolume(-0.04) | Out-Null
            return
        }
        if ($cmd -eq "like") {
            $res = [WinRtHelper.SpotifyCdp]::ToggleLike()
            if ($null -ne $res) {
                $global:currentIsLiked = [bool]$res
            } else {
                $global:currentIsLiked = -not $global:currentIsLiked
            }
            return
        }

        $mgrTask = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
        $mgr = AwaitTask $mgrTask ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]) 150
        $session = if ($mgr) { Find-BestSession $mgr } else { $null }
        if ($session) {
            if ($cmd -eq "playpause") {
                $session.TryTogglePlayPauseAsync() | Out-Null
            } elseif ($cmd -eq "next") {
                $session.TrySkipNextAsync() | Out-Null
            } elseif ($cmd -eq "prev") {
                $session.TrySkipPreviousAsync() | Out-Null
            } elseif ($cmd -eq "shuffle") {
                try {
                    $pb = $session.GetPlaybackInfo()
                    $cur = if ($pb) { [bool]$pb.IsShuffleActive } else { $false }
                    $session.TryChangeShuffleActiveAsync(-not $cur) | Out-Null
                } catch {}
            } elseif ($cmd -eq "repeat") {
                try {
                    $pb = $session.GetPlaybackInfo()
                    $curRep = if ($pb -and $pb.AutoRepeatMode) { $pb.AutoRepeatMode.ToString() } else { "None" }
                    $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::None
                    if ($curRep -eq "None") { 
                        $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::List 
                    } elseif ($curRep -eq "List") { 
                        $nextRep = [Windows.Media.MediaPlaybackAutoRepeatMode]::Track 
                    }
                    $session.TryChangeAutoRepeatModeAsync($nextRep) | Out-Null
                } catch {}
            }
        }
    } catch {}
}

Add-Type -AssemblyName PresentationCore

$global:SoundDir = Join-Path $PSScriptRoot "sounds"
if (-not (Test-Path $global:SoundDir)) {
    $global:SoundDir = "C:\Umbrella\scripts\media_bridge\sounds"
}
if (-not (Test-Path $global:SoundDir)) {
    $global:SoundDir = "D:\main\project\scriptForUmb\dynamicisland\media_bridge\sounds"
}

$global:SoundPlayers = @{}
$global:SoundPoolIndex = @{}

function Init-SoundPool {
    if (-not (Test-Path $global:SoundDir)) { return }
    $soundFiles = Get-ChildItem -Path $global:SoundDir -Filter "*.mp3"
    foreach ($file in $soundFiles) {
        $baseName = $file.BaseName
        $pool = @()
        $instances = 2
        if ($baseName -eq "wheel_notch" -or $baseName -eq "button_press" -or $baseName -eq "wheel_boundary_bump") {
            $instances = 4
        }
        for ($i = 0; $i -lt $instances; $i++) {
            try {
                $p = New-Object System.Windows.Media.MediaPlayer
                $p.Open([System.Uri]::new($file.FullName))
                $p.Volume = 0.5
                $pool += $p
            } catch {}
        }
        $global:SoundPlayers[$baseName] = $pool
        $global:SoundPoolIndex[$baseName] = 0
    }
}

function Play-AppleSound($name, $volume, $force = $false) {
    if (-not $name) { return }
    if (-not $force -and $name -ne "match_found") {
        if (-not [WinRtHelper.AppAudioControl]::IsDotaFocused()) {
            return
        }
    }
    $pool = $global:SoundPlayers[$name]
    if ($null -ne $pool -and $pool.Count -gt 0) {
        $idx = $global:SoundPoolIndex[$name]
        $player = $pool[$idx]
        $global:SoundPoolIndex[$name] = ($idx + 1) % $pool.Count
        try {
            $player.Volume = $volume
            $player.Position = [System.TimeSpan]::Zero
            $player.Play()
        } catch {}
    } else {
        $soundPath = Join-Path $global:SoundDir ($name + ".mp3")
        if (Test-Path $soundPath) {
            try {
                $p = New-Object System.Windows.Media.MediaPlayer
                $p.Open([System.Uri]::new($soundPath))
                $p.Volume = $volume
                $p.Play()
            } catch {}
        }
    }
}

Init-SoundPool
[WinRtHelper.AppAudioControl]::StartFocusWatcher()

$listener = $null

while ($true) {
    try {
        if ($null -eq $listener -or -not $listener.IsListening) {
            try { if ($listener) { $listener.Close() } } catch {}
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add("http://127.0.0.1:45455/")
            $listener.Start()
        }

        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $response.KeepAlive = $false
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.OutputStream.Close()
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
                    volume       = 100
                    shuffle      = $false
                    repeat       = 0
                    is_liked     = $global:currentIsLiked
                }
            }
            $json = $data | ConvertTo-Json -Compress -Depth 3
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
        } elseif ($path -match "^/media/(playpause|next|prev|shuffle|repeat|like|volup|voldown)$") {
            $cmd = $matches[1]
            $bump = ($request.QueryString["bump"] -eq "1")
            if ($cmd -eq "volup" -or $cmd -eq "voldown") {
                if ($bump) {
                    Play-AppleSound "wheel_boundary_bump" 0.65
                } else {
                    Play-AppleSound "wheel_notch" 0.45
                }
            }
            Handle-MediaCommand $cmd
            $curVol = [WinRtHelper.AppAudioControl]::GetAppVolume()
            $volInt = [int][Math]::Round($curVol * 100)
            
            $json = @{ status = "ok"; volume = $volInt; is_liked = $global:currentIsLiked } | ConvertTo-Json -Compress
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
        } elseif ($path -eq "/sound") {
            $soundName = $request.QueryString["name"]
            $volParam = $request.QueryString["vol"]
            $force = ($request.QueryString["force"] -eq "1")
            $vol = 0.5
            if ($volParam) {
                $parsedVol = 0.0
                if ([double]::TryParse($volParam, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedVol)) {
                    $vol = [Math]::Max(0.01, [Math]::Min(1.0, $parsedVol))
                }
            }
            Play-AppleSound $soundName $vol $force
            $json = '{"status":"ok"}'
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
        } elseif ($path -eq "/focus") {
            $isFoc = [WinRtHelper.AppAudioControl]::IsDotaFocused()
            $json = @{ status = "ok"; focused = $isFoc } | ConvertTo-Json -Compress
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
        } else {
            $response.StatusCode = 404
            $response.OutputStream.Close()
        }
    } catch {
        Start-Sleep -Milliseconds 100
    }
}
