# Install and remove Vital

## Install

1. Download `Vital.dmg` from [GitHub Releases](https://github.com/soumyyy/vital/releases/latest).
2. Open the disk image and drag **Vital** into **Applications**.
3. Eject the disk image. Open **Vital** from Applications or Spotlight.
4. Click the menu bar icon to open Overview. Click the icon again to close the panel.

Vital is a menu bar app. It has no permanent Dock icon. If Vital is already running, selecting it in Spotlight opens its panel.

The release requires Apple Silicon and macOS 14 or later. Physical testing currently covers an M3 MacBook Pro on macOS 27. Other models and the macOS 14/15 interface still need user verification. Missing sensors appear as unavailable. Fanless Macs do not offer manual fan control.

## Choose permissions

- **Launch at login:** open the three-dot menu and turn on **Launch at login**. This is optional.
- **Personal folders:** select **Scan** beside a folder to request access. Vital does not scan protected personal folders automatically.
- **Full Disk Access:** optional. Without it, unreadable files remain in **Other & unmeasured**.
- **Fan control:** open Heat, select **Turn on**, then approve Vital in System Settings if asked. Manual control is optional. Leave fans in Auto when testing another fan utility.

Vital sends no telemetry. It contacts GitHub when you request an update check, and downloads the archive only after you approve installation.

## Update

Select **Update Software…**, review the release, then select **Update and Restart**. If the app cannot replace itself in its installation folder, download the DMG and replace the app manually after quitting Vital.

## Remove

1. Return fans to Auto, if manual control is active.
2. Turn off **Launch at login** in Vital's menu.
3. Run this command to remove Vital's optional fan helper registration:

```sh
/Applications/Vital.app/Contents/MacOS/Vital --unregister-fan-helper
```

4. Quit Vital and move `/Applications/Vital.app` to Trash.

Removing Vital does not delete your files. The helper's private recovery record can remain under `/var/db/dev.soumya.vital`; an empty record contains no manual target or personal data.
