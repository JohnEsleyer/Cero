# Cero Journal — Mobile (Flutter)

Offline-first, block-based card journal with multi-workspace support and real-time device sync. This is the **source-of-truth server** — a Flutter app that stores all journal pages and cards in SQLite databases and runs a WebSocket server for desktop clients.

> **Upgrading**: See [root README](../README.md) for the full technical plan transitioning from single-text markdown to multi-workspace card-based editing with subpages and side pages.

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

- **SQLite** — pages + cards stored locally in dynamic `.db` workspace files
- **WebSocket server** (port 9090) — authenticates clients with a 4-digit PIN and syncs pages/cards in real time
- **UDP multicast** (239.255.255.250:9100) — discovery beacons broadcast every 2 seconds
- **Pairing flow** — pending connections require manual approval on the mobile screen

## Features

- Multi-workspace support (switch between `.db` files)
- Block-based card editor (markdown, images, subpage links)
- Hierarchical subpages (left sidebar) + contextual side pages (right sidebar)
- Infinite page nesting via `parent_id` + recursive tree rendering
- Emoji icons per page
- Soft-delete trash system (archive / restore / permanent delete)
- Revision-based conflict resolution
- Debounced saves (500ms)

## Key Files

| File | Purpose |
|---|---|
| `lib/models/page_model.dart` | `DbPage` data model |
| `lib/models/card_model.dart` | `Card` data model (planned) |
| `lib/services/database_service.dart` | SQLite CRUD, workspace switching, migration |
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
