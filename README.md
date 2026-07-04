# Cero Journal — Mobile (Flutter)

Offline-first, nested markdown journal with real-time device sync. This is the **source-of-truth server** — a Flutter app that stores all journal pages in a local SQLite database and runs a WebSocket server for desktop clients to connect to.

## Architecture

```
┌─────────────────────────────────┐
│  Cero Journal (Flutter Mobile)  │
│                                 │
│  ┌──────────┐  ┌─────────────┐  │
│  │ SQLite   │  │ WebSocket   │  │
│  │ (truth)  │  │ Server:9090 │  │
│  └──────────┘  └──────┬──────┘  │
│                       │         │
│  ┌──────────────────┐ │         │
│  │ UDP Multicast    │ │         │
│  │ Beacon :9100     │ │         │
│  └──────────────────┘ │         │
└────────────────────────┼────────┘
                         │ WebSocket
┌────────────────────────┼────────┐
│  Cero Desktop (Wails)  │        │
│  ┌─────────────────────┘        │
│  │  Svelte UI · Go Backend     │
│  └──────────────────────────────┘
```

- **SQLite** (`cero_journal.db`) — all pages stored locally, offline-first
- **WebSocket server** (port 9090) — authenticates clients with a 4-digit PIN and syncs pages in real time
- **UDP multicast** (239.255.255.250:9100) — discovery beacons broadcast every 2 seconds
- **Pairing flow** — pending connections require manual approval on the mobile screen

## Features

- Infinite page nesting via `parent_id` + recursive tree rendering
- Markdown editing with live preview
- Emoji icons per page
- Soft-delete trash system (archive / restore / permanent delete)
- Revision-based conflict resolution
- Debounced saves (500ms)

## Key Files

| File | Purpose |
|---|---|
| `lib/models/page_model.dart` | `DbPage` data model |
| `lib/services/database_service.dart` | SQLite CRUD + archive/restore |
| `lib/services/server_service.dart` | WebSocket server, UDP beacon, sync engine |
| `lib/main.dart` | App entry point, UI shell |

## Getting Started

```bash
flutter pub get
flutter run
```

Build for production:

```bash
flutter build apk          # Android
flutter build ios          # iOS
flutter build linux        # Linux
flutter build windows      # Windows
flutter build macos        # macOS
```
