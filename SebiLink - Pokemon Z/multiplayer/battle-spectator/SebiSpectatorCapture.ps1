param(
  [int]$TargetProcessId = 0,
  [long]$WindowHandle = 0,
  [string]$OutPath,
  [string]$StopPath,
  [int]$IntervalMs = 180,
  [int]$OutputWidth = 512,
  [int]$OutputHeight = 384,
  [switch]$SelfTest
)

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SebiSpectatorCaptureNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll")]
  public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  public static IntPtr FindWindowForProcess(uint processId) {
    IntPtr result = IntPtr.Zero;
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      if (!IsWindow(hWnd) || !IsWindowVisible(hWnd)) return true;
      uint owner = 0;
      GetWindowThreadProcessId(hWnd, out owner);
      if (owner != processId) return true;
      RECT rect;
      if (!GetClientRect(hWnd, out rect)) return true;
      if ((rect.Right - rect.Left) <= 0 || (rect.Bottom - rect.Top) <= 0) return true;
      result = hWnd;
      return false;
    }, IntPtr.Zero);
    return result;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }
}
"@

if ($SelfTest) {
  Write-Host "SebiSpectatorCapture.ps1 OK"
  exit 0
}

try {
  if (($TargetProcessId -le 0 -and $WindowHandle -eq 0) -or
      [string]::IsNullOrWhiteSpace($OutPath) -or
      [string]::IsNullOrWhiteSpace($StopPath)) {
    exit 2
  }

  $dir = Split-Path -Parent $OutPath
  if (![string]::IsNullOrWhiteSpace($dir) -and !(Test-Path -LiteralPath $dir)) {
    [void](New-Item -ItemType Directory -Path $dir -Force)
  }
  $IntervalMs = [Math]::Max(80, $IntervalMs)
  $OutputWidth = [Math]::Max(1, $OutputWidth)
  $OutputHeight = [Math]::Max(1, $OutputHeight)

  while (!(Test-Path -LiteralPath $StopPath)) {
    $tempPath = $null
    $sourceBitmap = $null
    $graphics = $null
    $outputBitmap = $null
    $outputGraphics = $null
    try {
      $proc = $null
      if ($TargetProcessId -gt 0) {
        $proc = Get-Process -Id $TargetProcessId -ErrorAction SilentlyContinue
        if ($null -eq $proc) { break }
      }

      $handle = [IntPtr]::Zero
      if ($WindowHandle -ne 0) {
        $handle = [IntPtr]$WindowHandle
        if ($TargetProcessId -gt 0) {
          $handleProcessId = [uint32]0
          [void][SebiSpectatorCaptureNative]::GetWindowThreadProcessId($handle, [ref]$handleProcessId)
          if ([int]$handleProcessId -ne $TargetProcessId) {
            $handle = [IntPtr]::Zero
          }
        }
      }
      if (($handle -eq [IntPtr]::Zero -or ![SebiSpectatorCaptureNative]::IsWindow($handle)) -and $null -ne $proc) {
        $handle = $proc.MainWindowHandle
      }
      if (($handle -eq [IntPtr]::Zero -or ![SebiSpectatorCaptureNative]::IsWindow($handle)) -and $TargetProcessId -gt 0) {
        $handle = [SebiSpectatorCaptureNative]::FindWindowForProcess([uint32]$TargetProcessId)
      }
      if ($handle -eq [IntPtr]::Zero -or ![SebiSpectatorCaptureNative]::IsWindow($handle)) {
        Start-Sleep -Milliseconds $IntervalMs
        continue
      }

      $rect = New-Object SebiSpectatorCaptureNative+RECT
      $point = New-Object SebiSpectatorCaptureNative+POINT
      if (![SebiSpectatorCaptureNative]::GetClientRect($handle, [ref]$rect) -or
          ![SebiSpectatorCaptureNative]::ClientToScreen($handle, [ref]$point)) {
        Start-Sleep -Milliseconds $IntervalMs
        continue
      }

      $width = [Math]::Max(1, $rect.Right - $rect.Left)
      $height = [Math]::Max(1, $rect.Bottom - $rect.Top)
      $sourceBitmap = New-Object System.Drawing.Bitmap($width, $height)
      $graphics = [System.Drawing.Graphics]::FromImage($sourceBitmap)
      try {
        $graphics.CopyFromScreen($point.X, $point.Y, 0, 0, (New-Object System.Drawing.Size($width, $height)))
        $tempPath = $OutPath + "." + [Guid]::NewGuid().ToString("N") + ".tmp.png"
        $outputBitmap = New-Object System.Drawing.Bitmap($OutputWidth, $OutputHeight)
        $outputGraphics = [System.Drawing.Graphics]::FromImage($outputBitmap)
        try {
          $outputGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
          $outputGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
          $outputGraphics.DrawImage(
            $sourceBitmap,
            (New-Object System.Drawing.Rectangle(0, 0, $OutputWidth, $OutputHeight)),
            (New-Object System.Drawing.Rectangle(0, 0, $width, $height)),
            [System.Drawing.GraphicsUnit]::Pixel
          )
          $outputBitmap.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
          if ($null -ne $outputGraphics) { $outputGraphics.Dispose() }
          if ($null -ne $outputBitmap) { $outputBitmap.Dispose() }
        }
        Move-Item -LiteralPath $tempPath -Destination $OutPath -Force
      } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $sourceBitmap) { $sourceBitmap.Dispose() }
      }
    } catch {
      if ($null -ne $tempPath -and (Test-Path -LiteralPath $tempPath)) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
      }
    }

    Start-Sleep -Milliseconds $IntervalMs
  }
  exit 0
} catch {
  exit 1
}
