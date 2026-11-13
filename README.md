# iCloud Passwords for Chrome on Windows

Fill the iCloud Passwords verification code when you open a fresh Chrome session. Open Chrome from your usual shortcut, then click the iCloud Passwords extension when you need it. The helper waits as long as Chrome stays open and exits after one fill attempt or when all Chrome windows close.

## Requirements

- Windows PowerShell 5.1
- Google Chrome and the iCloud Passwords extension
- iCloud for Windows with Passwords enabled
- The English iCloud verification dialog

## Try it

Clone the repo and double-click **Open Chrome with iCloud.cmd** after closing all Chrome windows. Once Chrome opens, click the iCloud Passwords extension icon. The extension submits automatically after the sixth digit.

## Use your existing taskbar shortcut

1. Find the pinned **Google Chrome** shortcut. On Windows, right-click its taskbar icon, then right-click **Google Chrome** in the menu and choose **Properties**.
2. Save the original **Target** so you can restore it later.
3. Set **Target** to the following, substituting the full path to your clone.

   ```text
   %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -MTA -WindowStyle Hidden -File "C:\path\to\icloud-chrome-verification\Watch-ICloudChromeVerification.ps1" -Mode Launch -ShortcutLocation taskbar
   ```

4. Close all Chrome windows, reopen Chrome from the taskbar, and click the extension once. Keep Chrome in the foreground while it fills.

If Chrome already has a window open, the shortcut launches Chrome normally and the helper exits. To undo the setup, restore the shortcut's original Target.

## Manual testing

From the repo directory, start one of these modes and then open the extension.

```powershell
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Detect
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Check
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Fill
```

| Mode | Behavior |
| --- | --- |
| `Detect` | Confirms the Windows code dialog can be read. |
| `Check` | Also confirms the first extension field has focus. |
| `Fill` | Enters the code once when the dialog and destination both match. |

Each manual run waits 45 seconds by default. Use `-TimeoutSeconds 90` for more time. If focus changes during entry, finish manually or start a fresh challenge.

## How it works

The launcher checks for Chrome windows twice a second and uses Windows UI Automation only when the iCloud helper has a visible dialog. It verifies the iCloud helper process, the dialog contents, Chrome's foreground window, the exact extension URL, and the focused PIN field before entry. The extension advances through the six fields and handles submission. The code stays in memory for the attempt and is never logged, saved, or copied to the clipboard.
