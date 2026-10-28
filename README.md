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
- **Clean:** a checklist where safe caches come pre-checked. You see the size of each item before deleting, and the real space freed afterwards.
- **node_modules finder:** lists every `node_modules` folder in your home with its size and when the project was last touched. Press `o` to check the ones idle for 3+ months.
- **Honest results:** if something can't be deleted (in use, or no permission) it tells you instead of showing a fake ✓.
- **Keyboard driven:** arrow keys, space, enter. Works in Terminal, iTerm2, Warp, VS Code, etc.

## What it can clean

| Item | Where | Safe? |
|---|---|---|
| Chrome leftover copies | `/private/var/folders/…/X/com.google.Chrome.code_sign_clone` | Yes. Chrome leaves a copy of itself here every time it updates or relaunches without being fully quit. These can add up to many GB. Only cleaned while Chrome is closed. |
| Chrome Service Worker | `~/Library/Application Support/Google/Chrome/*/Service Worker` | Yes. Offline website cache; you stay logged in. Only cleaned while Chrome is closed. |
| App caches | `~/Library/Caches` | Yes, apps rebuild it |
| Logs | `~/Library/Logs` | Yes |
| Dev tool caches | `~/.cache` | Yes (puppeteer, huggingface, etc. download again) |
| npm cache | `npm cache clean --force` | Yes |
| pnpm store | `pnpm store prune` | Yes, only unused packages |
| Gradle cache | `~/.gradle/caches` | Yes |
| macOS photo analysis cache | `~/Library/Containers/com.apple.mediaanalysisd` | Yes, macOS rebuilds it |
| VS Code cache | `~/Library/Application Support/Code/Cache…` | Yes |
| Discord / Spotify cache | `~/Library/Application Support/…` | Yes |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | Yes |
| Homebrew | `brew cleanup -s --prune=all` | Yes |
| Stremio | `~/Library/Application Support/stremio-server` | Yes, cached movies |
| Trash | `~/.Trash` | **Permanent.** Never pre-checked, with an extra warning |

Items that don't exist on your Mac are hidden automatically.

The scan also shows things the script won't delete for you, so you can decide: Downloads, Desktop, Documents, WhatsApp media, iOS Simulators, Xcode Archives and downloaded macOS updates.

## Safety

- Nothing is deleted without a confirmation screen (`y` to confirm).
- It only touches the folders listed above, never system files.
- No `sudo`, it only works with your own user's files.
- Chrome items are locked while Chrome is running.

## Full Disk Access

macOS blocks terminals from reading some folders, like the Trash. If an item shows `?` as its size, give your terminal app Full Disk Access:

**System Settings → Privacy & Security → Full Disk Access →** enable your terminal (Terminal, iTerm, Warp…), then restart it.

## Notes

- **Sizes can look bigger than they are.** APFS shares data between cloned files, so a folder can report more than the space you'll actually get back. The summary at the end shows the real change in free space.
- **Quit Chrome now and then** (Cmd+Q, not just closing the window). Leaving it open for days is what makes the leftover copies pile up.
- Requires macOS and the bash that ships with it (3.2+). No Homebrew or other tools needed.

## License

[MIT](LICENSE)
