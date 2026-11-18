# macOS Disk Cleaner

An interactive terminal app to **free up disk space on macOS**. It shows what is eating your disk, including the hidden stuff that ends up as "System Data" in Storage settings, and lets you pick what to delete.

One bash script, no dependencies, nothing to install. It never deletes anything without asking.

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ✻ macOS Disk Cleaner                                            macOS 26.6.2 │
│                                                                              │
│ █████████████████████████████████████████████████████▊──────────  84% used   │
│ 36.3 GB free of 228.3 GB                                                     │
╰──────────────────────────────────────────────────────────────────────────────╯

  What to delete
  checked items are safe, the system rebuilds them · Trash is never pre-checked

  ❯ ◉ App caches                        3.7 GB  ███████████████████████▉──────
    ◉ pnpm store                        3.5 GB  ██████████████████████▊───────
    ◉ Chrome leftover copies            2.1 GB  █████████████▋────────────────
    ◉ ~/.cache                          1.0 GB  ██████▍───────────────────────
    ◉ npm cache                         183 MB  █▏────────────────────────────
    ○ Trash                                  ?  ──────────────────────────────

  ⎿  ~/Library/Caches · apps rebuild it on their own

  Selected: 5 · ~10.5 GB
  ────────────────────────────────────────────────────────────────────────────
  ↑↓ · space toggle · a all · n none · enter delete · q back
```

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/coradini1/macos-disk-cleaner/main/cleaner.sh -o cleaner.sh
bash cleaner.sh
```

Or clone the repo:

```bash
git clone https://github.com/coradini1/macos-disk-cleaner.git
cd macos-disk-cleaner
bash cleaner.sh
```

## Features

- **Scan:** a bar chart of the biggest space users, split into "cleanable" and "your call".
- **Clean:** a checklist of caches and leftovers where the safe ones come pre-checked. You see the size of each item before deleting, and the real space freed afterwards.
- **Large files:** finds every file over 500 MB in your home folder (videos, VM disks, game dumps, old backups…) with when it was last modified.
- **Installers & archives:** old `.dmg`, `.pkg`, `.iso` and `.xip` installers plus big `.zip`/`.rar`/`.7z` files lying around in Downloads, Desktop and Documents.
- **Apps:** every app sorted by when you last opened it, so you can spot the ones you forgot about. Apple's own apps are never listed.
- **node_modules finder:** every `node_modules` folder in your home with its size and when the project was last touched.
- **Move to Trash or delete:** for files and apps you choose between moving them to the Trash (undoable) or deleting them for good.
- **Honest results:** if something can't be deleted (in use, or no permission) it tells you instead of showing a fake ✓.
- **Keyboard driven:** arrow keys, space, enter. Press `o` in any list to check the old items. Works in Terminal, iTerm2, Warp, VS Code, etc.

## What it can clean

| Item | Where | Pre-checked? |
|---|---|---|
| App leftover copies | `/private/var/folders/…/X/*.code_sign_clone` | Yes. Chrome (and other apps) leave a copy of themselves here every time they update or relaunch without being fully quit. These can add up to many GB. Copies still in use are kept. |
| Chrome Service Worker | `~/Library/Application Support/Google/Chrome/*/Service Worker` | Yes. Offline website cache; you stay logged in. Only while Chrome is closed. |
| App caches | `~/Library/Caches` | Yes |
| Logs | `~/Library/Logs` | Yes |
| Dev tool caches | `~/.cache` (puppeteer, huggingface…) | Yes |
| npm / pnpm / Bun | `npm cache clean`, `pnpm store prune`, `~/.bun/install/cache` | Yes |
| Rust / Go / Conda | `~/.cargo/registry`, `go clean -modcache`, `conda clean --all` | Yes |
| Gradle | `~/.gradle/caches` | Yes |
| macOS photo analysis cache | `~/Library/Containers/com.apple.mediaanalysisd` | Yes |
| Mail attachments cache | `~/Library/Containers/com.apple.mail/…/Mail Downloads` | Yes, attachments stay in the emails |
| VS Code, Discord, Spotify caches | `~/Library/Application Support/…` | Yes |
| Xcode DerivedData & device support | `~/Library/Developer/Xcode/…` | Yes |
| Broken iOS simulators | `xcrun simctl delete unavailable` | Yes |
| iPhone/iPad update files | `~/Library/iTunes/… Software Updates` | Yes |
| Homebrew | `brew cleanup -s --prune=all` | Yes |
| Stremio | `~/Library/Application Support/stremio-server` | Yes |
| Docker | `docker system prune -a` | No, you'll have to pull images again |
| Android emulator images | `~/Library/Android/sdk/system-images` | No, re-download from Android Studio |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | No, you may still need them |
| iPhone/iPad backups | `~/Library/Application Support/MobileSync/Backup` | No, make sure you have another backup |
| Trash | `~/.Trash` | **No. Permanent**, with an extra warning |

Items that don't exist on your Mac are hidden automatically.

The scan also shows big folders the script won't clean for you, so you can decide: Downloads, Desktop, Documents, Pictures, Movies, Music, WhatsApp media and downloaded macOS updates. Use **Large files** to find exactly what is inside them.

## Safety

- Nothing is deleted without a confirmation screen (`y` to confirm).
- Cleaning only touches the folders listed above, never system files. Apple's own apps are never offered for removal, and running apps are locked.
- No `sudo`, it only works with your own user's files.
- Chrome items are locked while Chrome is running.

## Full Disk Access

macOS blocks terminals from reading some folders, like the Trash. If an item shows `?` as its size, give your terminal app Full Disk Access (the Trash can still be emptied without it, through Finder):

**System Settings → Privacy & Security → Full Disk Access →** enable your terminal (Terminal, iTerm, Warp…), then restart it.

## Notes

- **Sizes can look bigger than they are.** APFS shares data between cloned files, so a folder can report more than the space you'll actually get back. The summary at the end shows the real change in free space.
- **Quit Chrome now and then** (Cmd+Q, not just closing the window). Leaving it open for days is what makes the leftover copies pile up.
- Requires macOS and the bash that ships with it (3.2+). No Homebrew or other tools needed.

## License

[MIT](LICENSE)
