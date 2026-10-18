# Maclip: App Store Connect listing

Copy each field into App Store Connect (My Apps → Maclip). Limits are Apple's.

## App information

| Field | Value |
| --- | --- |
| Name (30) | Maclip – Clipboard History |
| Subtitle (30) | Copy, search & paste anything |
| Bundle ID | com.clipboard.Maclip |
| SKU | maclip |
| Primary category | Productivity |
| Secondary category | Utilities |
| Content rights | Does not contain third-party content |
| Age rating | 4+ (answer "None" / "No" to every question) |
| Price | Free |
| Copyright | 2026 Oghenefejiro Cornelius |

## URLs

| Field | Value |
| --- | --- |
| Support URL | https://dcloser.github.io/Maclip/ |
| Marketing URL (optional) | https://dcloser.github.io/Maclip/ |
| Privacy Policy URL | https://dcloser.github.io/Maclip/privacy.html |

These go live once GitHub Pages is turned on for the repo (Settings → Pages → Deploy from a branch → `main`, folder `/docs`).

## Promotional text (170, can be changed without a new review)

Everything you copy, one shortcut away. Press ⇧⌘V to search your text and image history and paste it right where you are typing. Private, fast and free.

## Description (4000)

Maclip brings the clipboard history you know from Windows (Win+V) to your Mac, and makes it better.

Every piece of text and every image you copy is saved. Press ⇧⌘V in any app and a small panel opens right next to your pointer, with your latest copies at the top. Pick one with the arrow keys or a click and Maclip pastes it straight into the app you were using.

FIND ANYTHING YOU COPIED
• Start typing to search your whole history instantly, text and images alike
• Image copies, such as screenshots and pictures from the web, show as thumbnails
• Jump to any of the top nine items with ⌘1–⌘9

KEEP WHAT MATTERS
• Pin the snippets you use all the time so they always stay on top
• Delete single items or clear everything except your pins
• Copying something again moves it back to the top, with no duplicates

MAKE IT YOURS
• Choose how long history is kept: forever, a day, a week, a month or a year
• Choose how many items to keep, from 25 to 1,000
• Light, dark or match your Mac
• Set any keyboard shortcut you like
• Launch automatically at login

PRIVATE BY DESIGN
• Your history never leaves your Mac. Maclip has no network access, no accounts, no analytics and no ads.
• Items that password managers mark as private are never recorded.
• Everything is stored in Maclip's own protected container.

Maclip lives quietly in the menu bar and uses almost no resources. Auto-paste is optional: it uses macOS's Accessibility permission only to press ⌘V for you. Without it, Maclip copies the item and you paste it yourself.

Maclip is free and open source: github.com/dCloser/Maclip

## Keywords (100, comma-separated, no spaces)

clipboard,history,manager,paste,copy,snippets,pasteboard,win+v,pin,text,image,screenshot,shortcut

## What's New (version 1.0)

First release of Maclip.

## App Privacy questionnaire

Data collection: **No, we do not collect data from this app.** The result shown on the store is "Data Not Collected".

## App Review information

**Sign-in required:** No.

**Notes:**

> Maclip is a clipboard history utility that lives in the menu bar (clipboard icon); it has no Dock icon or main window.
>
> To try it: copy a few pieces of text (and optionally an image), then press Shift-Command-V in any app, such as TextEdit. A panel lists the copied items. Choose one with the arrow keys and Return, or a click, to paste it. Typing filters the list. Preferences are in the menu bar menu.
>
> Accessibility permission is optional. Maclip uses it only to post a single Command-V keystroke to the frontmost app, so the chosen item is pasted automatically (via CGRequestPostEventAccess / CGEventPost). Maclip explains this in a welcome window before asking. Without the permission, choosing an item copies it to the clipboard and the user pastes manually. Maclip does not read the screen or other apps' content.
>
> All data stays on the device in the app's sandbox container. The app has no network entitlement.

**Contact:** your name, phone number and email (App Store Connect asks for these; they are not shown publicly).

## Screenshots

`AppStore/screenshots/` contains 2880 × 1800 PNGs: upload them in this order. Regenerate with:

```bash
swift build && "$(swift build --show-bin-path)/Maclip" --snapshot build/snapshots && swift AppStore/make-screenshots.swift
```
