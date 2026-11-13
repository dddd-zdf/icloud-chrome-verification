#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Check', 'Fill', 'Launch')]
    [string]$Mode = 'Detect',
    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 45,
    [ValidateSet('taskbar', 'start-menu')]
    [string]$ShortcutLocation
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    if ($Mode -ne 'Detect' -and -not ('ICloudPinNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ICloudPinNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

    public static HashSet<uint> VisibleWindowOwners(string className, bool includeOwned)
    {
        var owners = new HashSet<uint>();
        var name = new StringBuilder(64);
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            if (IsWindowVisible(window) && (includeOwned || GetWindow(window, 4) == IntPtr.Zero) &&
                GetClassName(window, name, name.Capacity) > 0 && name.ToString() == className)
            {
                uint process;
                if (GetWindowThreadProcessId(window, out process) != 0) owners.Add(process);
            }
            return true;
        }, IntPtr.Zero);
        return owners;
    }

    [DllImport("user32.dll")]
    private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr window, uint flags);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint code, uint mapType);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    [DllImport("user32.dll", EntryPoint = "PostMessageW")]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    public static IntPtr GetVerifiedFocus(IntPtr window, uint thread, uint owner)
    {
        var info = new GuiThreadInfo { Size = (uint)Marshal.SizeOf(typeof(GuiThreadInfo)) };
        if (!GetGUIThreadInfo(thread, ref info) || info.Focus == IntPtr.Zero ||
            GetAncestor(info.Focus, 2) != window) return IntPtr.Zero;
        uint process;
        if (GetWindowThreadProcessId(info.Focus, out process) != thread || process != owner ||
            GetForegroundWindow() != window) return IntPtr.Zero;
        return info.Focus;
    }

    public static bool PostDigit(IntPtr window, uint thread, uint owner, char digit)
    {
        if (digit < '0' || digit > '9' ||
            GetAsyncKeyState(0x10) < 0 || GetAsyncKeyState(0x11) < 0 ||
            GetAsyncKeyState(0x12) < 0) return false;
        IntPtr focus = GetVerifiedFocus(window, thread, owner);
        if (focus == IntPtr.Zero) return false;

        // Address the verified Chrome HWND directly. Global keyboard injection
        // could deliver the digit to another application after a focus switch.
        var key = new IntPtr(digit);
        int keyData = 1 | ((int)MapVirtualKey(digit, 0) << 16);
        return PostMessage(focus, 0x0100, key, new IntPtr(keyData)) &&
               PostMessage(focus, 0x0101, key, new IntPtr(keyData | unchecked((int)0xC0000000)));
    }
}
'@
    }
} catch {
    Write-Host 'Could not initialize Windows accessibility. Run this in Windows PowerShell 5.1.'
    exit 1
}


function Get-ICloudVerificationCode {
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $any = [System.Windows.Automation.Condition]::TrueCondition
    $dialogClass = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, '#32770'
    )
    $textType = [System.Windows.Automation.ControlType]::Text
    $buttonType = [System.Windows.Automation.ControlType]::Button
    $paneType = [System.Windows.Automation.ControlType]::Pane
    $codeShape = '\A[0-9]{3}\p{Zs}[0-9]{3}\z'
    $result = $null

    foreach ($dialog in $desktop.FindAll('Children', $dialogClass)) {
        try {
            $window = $dialog.Current
            if ($window.IsOffscreen) { continue }
            $process = Get-Process -Id $window.ProcessId -ErrorAction Stop
            if ($process.ProcessName -ne 'iCloudPasswordsExtensionHelper' -or
                $process.Path -notmatch $iCloudPathPattern) { continue }

            $hasPrompt = $false
            $hasDismiss = $false
            $codeControls = 0
            $pin = $null

            # The native dialog's child controls can appear as Panes through
            # managed UIA, including the prompt, code and Dismiss button.
            foreach ($child in $dialog.FindAll('Children', $any)) {
                $info = $child.Current
                if ($info.IsOffscreen -or $info.ProcessId -ne $window.ProcessId) { continue }
                if (($info.ControlType -eq $textType -or $info.ControlType -eq $paneType) -and
                    [string]$info.Name -match '\bEnter\s+this\s+verification\s+code\b.*?\bChrome\s+extension\b') {
                    $hasPrompt = $true
                } elseif (($info.ControlType -eq $buttonType -or $info.ControlType -eq $paneType) -and
                          $info.Name -ceq 'Dismiss') {
                    $hasDismiss = $true
                } elseif (($info.ControlType -eq $textType -or $info.ControlType -eq $paneType) -and
                          [string]$info.Name -match $codeShape) {
                    $codeControls++
                    $pin = $info.Name -replace '\p{Zs}', ''
                }
            }
            if ($hasPrompt -and $hasDismiss -and $codeControls -eq 1) {
                if ($null -ne $result) { return }
                $result = $pin
            }
        } catch {
            # The dialog can close while the accessibility tree is being read.
            continue
        }
    }
    return $result
}

function Get-ChromePinTarget {
    param(
        [ValidateRange(0, 5)][int]$Index = 0,
        $ExpectedDocument
    )

    try {
        $window = [ICloudPinNative]::GetForegroundWindow()
        if ($window -eq [IntPtr]::Zero) { return }
        [uint32]$owner = 0
        $thread = [ICloudPinNative]::GetWindowThreadProcessId($window, [ref]$owner)
        if ($thread -eq 0) { return }
        $process = Get-Process -Id $owner -ErrorAction Stop
        if ($process.ProcessName -ne 'chrome' -or
            $process.Path -notmatch '\\Google\\Chrome\\Application\\chrome\.exe$') { return }

        $root = [System.Windows.Automation.AutomationElement]::FromHandle($window)
        $typeProperty = [System.Windows.Automation.AutomationElement]::ControlTypeProperty
        $documentType = [System.Windows.Automation.PropertyCondition]::new(
            $typeProperty, [System.Windows.Automation.ControlType]::Document
        )
        $fieldId = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, "PIN$Index"
        )
        $found = $null
        foreach ($document in $root.FindAll('Descendants', $documentType)) {
            $docInfo = $document.Current
            if ($docInfo.IsOffscreen -or $docInfo.ProcessId -ne $owner) { continue }
            if ($null -ne $ExpectedDocument -and
                -not [System.Windows.Automation.Automation]::Compare($document, $ExpectedDocument)) { continue }

            $value = $null
            if (-not $document.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$value)) { continue }
            if ($value.Current.Value -cnotin @(
                'chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/page_popup.html',
                'chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/page_popup.html?popupWindow=1'
            )) { continue }

            $fields = $document.FindAll('Descendants', $fieldId)
            if ($fields.Count -ne 1) { continue }
            $field = $fields[0].Current
            if ($field.ProcessId -ne $owner -or $field.ControlType -ne [System.Windows.Automation.ControlType]::Edit -or
                $field.IsOffscreen -or -not $field.IsEnabled -or -not $field.HasKeyboardFocus) { continue }
            if ($null -ne $found) { return }
            $found = [pscustomobject]@{ Window = $window; Thread = $thread; Owner = $owner; Document = $document }
        }

        if ($null -ne $found -and [ICloudPinNative]::GetVerifiedFocus($window, $thread, $owner) -ne [IntPtr]::Zero) {
            return $found
        }
    } catch {
        # The popup or focus can disappear between accessibility calls.
        return
    }
}

function Send-ChromePin {
    param([string]$Pin, $Target)

    if ($Pin -cnotmatch '\A[0-9]{6}\z') { return $false }
    for ($index = 0; $index -lt 6; $index++) {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            $current = Get-ChromePinTarget -Index $index -ExpectedDocument $Target.Document
            if ($null -ne $current) { break }
            if ([ICloudPinNative]::GetForegroundWindow() -ne $Target.Window) { return $false }
            if ($index -eq 0) { return $false }
            Start-Sleep -Milliseconds 25
        } while ($clock.ElapsedMilliseconds -lt 500)

        if ($null -eq $current -or $current.Window -ne $Target.Window -or
            -not [ICloudPinNative]::PostDigit($current.Window, $current.Thread, $current.Owner, $Pin[$index])) { return $false }
    }
    return $true
}

function Test-VisibleWindowOwner {
    param([string]$ProcessName, [string]$WindowClass, [string]$PathPattern, [switch]$IncludeOwned)

    $owners = [ICloudPinNative]::VisibleWindowOwners($WindowClass, $IncludeOwned.IsPresent)
    foreach ($owner in $owners) {
        $process = Get-Process -Id $owner -ErrorAction SilentlyContinue
        if ($null -ne $process -and $process.ProcessName -eq $ProcessName -and
            $process.Path -match $PathPattern) { return $true }
    }
    return $false
}

function Test-ChromeWindowOpen {
    return Test-VisibleWindowOwner -ProcessName 'chrome' -WindowClass 'Chrome_WidgetWin_1' `
        -PathPattern '\\Google\\Chrome\\Application\\chrome\.exe$'
}

function Start-Chrome {
    $key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    $registered = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($key)
    if ($null -eq $registered) { $registered = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key) }
    $paths = @(
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    if ($null -ne $registered) {
        try { $paths = @([string]$registered.GetValue('')) + $paths }
        finally { $registered.Dispose() }
    }
    foreach ($path in $paths) {
        if ($path -match '\\Google\\Chrome\\Application\\chrome\.exe$' -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            if ($ShortcutLocation) {
                Start-Process -FilePath $path -ArgumentList "--source-shortcut-location=$ShortcutLocation"
            } else {
                Start-Process -FilePath $path
            }
            return
        }
    }
    throw 'Chrome could not be found.'
}

function Invoke-LaunchedChromeVerification {
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-ChromeWindowOpen)) {
        if ($clock.Elapsed.TotalSeconds -ge 30) { return 2 }
        Start-Sleep -Milliseconds 250
    }

    $pin = $null
    try {
        while (Test-ChromeWindowOpen) {
            if (Test-VisibleWindowOwner -ProcessName 'iCloudPasswordsExtensionHelper' `
                -WindowClass '#32770' -IncludeOwned -PathPattern $iCloudPathPattern) {
                $pin = Get-ICloudVerificationCode
                if ($null -ne $pin) {
                    $target = Get-ChromePinTarget
                    if ($null -ne $target) {
                        if (Send-ChromePin -Pin $pin -Target $target) { return 0 }
                        # Leave any partial entry to the user.
                        return 3
                    }
                    $pin = $null
                }
            }
            Start-Sleep -Milliseconds 500
        }
        return 0
    } finally {
        $pin = $null
    }
}


function Invoke-ICloudVerification {
    Write-Host "Watching for the iCloud verification dialog for $TimeoutSeconds seconds. Trigger verification in Chrome."
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $sawDialog = $false
    $pin = $null
    try {
        do {
            $pin = Get-ICloudVerificationCode
            if ($null -ne $pin) {
                if (-not $sawDialog) {
                    Write-Host 'Read the iCloud verification code through Windows accessibility.'
                    $sawDialog = $true
                }
                if ($Mode -eq 'Detect') { return 0 }

                $target = Get-ChromePinTarget
                if ($null -ne $target) {
                    if ($Mode -eq 'Check') {
                        Write-Host 'Verified the focused iCloud Passwords field in Chrome. Check mode entered nothing.'
                        return 0
                    }
                    if (Send-ChromePin -Pin $pin -Target $target) {
                        Write-Host 'Sent six digits to iCloud Passwords. Check the result in Chrome.'
                        return 0
                    }
                    Write-Host 'Entry stopped before completion. Check the extension and finish verification manually.'
                    return 3
                }
            }
            $pin = $null
            Start-Sleep -Milliseconds 250
        } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)

        if ($sawDialog) {
            Write-Host 'Timed out waiting for the verified Chrome field. Finish verification manually.'
        } else {
            Write-Host 'Timed out without finding a readable iCloud verification dialog.'
        }
        return 2
    } finally {
        $pin = $null
    }
}

$iCloudPathPattern = '\\(?:WindowsApps\\AppleInc\.iCloud_[^\\]+_nzyj5cx40ttqa|Common Files\\Apple\\Internet Services)\\'
$lock = $null
$ownsLock = $false
try {
    if ($Mode -eq 'Launch') {
        $wasOpen = Test-ChromeWindowOpen
        Start-Chrome
        if ($wasOpen) { exit 0 }
    }
    if ($Mode -in 'Launch', 'Fill') {
        $lock = New-Object System.Threading.Mutex($false, 'Local\ICloudPasswordsChromeVerification')
        try { $ownsLock = $lock.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $ownsLock = $true }
        if (-not $ownsLock) {
            Write-Host 'An iCloud fill watcher is already running in this Windows session.'
            exit 1
        }
    }
    if ($Mode -eq 'Launch') { exit (Invoke-LaunchedChromeVerification) }
    exit (Invoke-ICloudVerification)
} catch {
    Write-Host 'The verification watcher stopped after an unexpected error.'
    exit 1
} finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    if ($null -ne $lock) { $lock.Dispose() }
}
