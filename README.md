# Class Recordings

Phone-friendly player for class recordings (Usool, Tafseer, Hidayatun Nahv).

- `index.html` is the whole site (no build step).
- `recordings.json` lists every session: date, length, and where its audio lives.
- Audio files are not stored in this repo (about 8 GB). Set `audioBase` or the Google Drive fields in `recordings.json` to point at wherever they are hosted.

## iPhone app (`app/`)

"Zainab Center Recordings" iPhone app (SwiftUI, iOS 17+). Same look as the site.
Lists the recordings in the shared Google Drive folder, downloads them all to the phone
(or pick one by one), and plays them offline with lock-screen controls.

Build: `cd app && xcodegen && open ZainabCenterRecordings.xcodeproj`
