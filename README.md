# iCloud Passwords verification helper for Chrome

This Windows helper fills in the six-digit code that iCloud Passwords shows when you verify the Chrome extension. Open Chrome with the included launcher, then click the iCloud Passwords icon when you need it.

## What you need

- Windows with Windows PowerShell 5.1
- Google Chrome with the iCloud Passwords extension installed
- iCloud for Windows, signed in with Passwords enabled
- An iCloud verification dialog displayed in English

## Get started

1. [Download the ZIP](https://github.com/dddd-zdf/icloud-chrome-verification/archive/refs/heads/main.zip) and extract it. Keep the two script files together.
2. Close all Chrome windows.
3. Double-click **Open Chrome with iCloud.cmd** in the extracted folder.
4. Click **iCloud Passwords** in Chrome's toolbar or Extensions menu. Keep Chrome in the foreground while the helper fills the code. The extension submits it after the sixth digit.

You can click the extension later in the same Chrome session. The helper waits until it makes one fill attempt or you close all Chrome windows. If Chrome already had a window open when you ran the launcher, close all Chrome windows and try again.

## Use your pinned Chrome shortcut

If you want the helper to start from your existing taskbar shortcut:

1. Move the extracted folder somewhere you plan to keep it.
2. Right-click the pinned Chrome icon, then right-click **Google Chrome** in the menu and choose **Properties**.
3. Copy the original **Target** somewhere safe so you can restore it.
4. Replace **Target** with the line below. Change the quoted path to the full path to your copy of the PowerShell script.

   ```text
   %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -MTA -WindowStyle Hidden -File "C:\path\to\icloud-chrome-verification\Watch-ICloudChromeVerification.ps1" -Mode Launch -ShortcutLocation taskbar
   ```

5. Click **OK**, close all Chrome windows, and reopen Chrome from the pinned icon.

To undo the change, paste the original **Target** back into the shortcut properties.

## If the code does not fill

- Make sure you started Chrome with the launcher or the updated shortcut after closing all Chrome windows.
- Keep Chrome in the foreground and leave focus in the first verification field.
- If Windows PowerShell reports that the downloaded script is blocked, right-click the ZIP, choose **Properties**, select **Unblock** if shown, and extract it again.
- If only some digits appear, finish entering the code manually or start a fresh verification prompt.

## How it handles the code

The helper reads the code from Apple's Windows dialog using Windows accessibility. Before typing, it checks the foreground Chrome window, the iCloud Passwords extension URL, and the focused verification field. It keeps the code in memory for the attempt and never logs it, saves it to disk, or copies it to the clipboard.

## Manual checks

Run one command from the extracted folder, then open the extension to trigger verification.

```powershell
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Detect
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Check
powershell.exe -NoProfile -MTA -File .\Watch-ICloudChromeVerification.ps1 -Mode Fill
```

- **Detect** checks whether the helper can read the Windows dialog.
- **Check** also verifies that the first extension field has focus.
- **Fill** attempts to enter the code once both checks pass.

Each manual run waits 45 seconds by default. Add `-TimeoutSeconds 90` to wait longer.
