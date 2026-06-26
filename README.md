
# Excalidraw — Self-Hosted Stack

A fully self-contained Excalidraw deployment with no dependency on Firebase or any Google services. All data stays on your machine.

## What's included

| Service | Image | Role |
|---------|-------|------|
| `excalidraw` | Built from `../excalidraw` | The drawing app, served by nginx on port 3000 |
| `excalidraw-storage` | Built from `../excalidraw-storage-backend` | HTTP API that stores rooms and files |
| `excalidraw-room` | Built from `../excalidraw-room` | Socket.io relay for real-time collaboration |
| `redis` | `redis:7-alpine` | Persistent key-value store backing the storage service |

Collaboration room state and embedded images are stored in Redis and survive container restarts. The Docker volume `excalidraw-stack_redis-data` holds all persistent data.

## Requirements

- Docker Desktop with WSL 2 integration enabled
- Git (for submodule checkout)

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/nomdetom/excalidraw-stack
cd excalidraw-stack
```

The three source repos are included as submodules:

```
excalidraw-stack/
├── excalidraw/                   ← patched upstream (firebase → HTTP backend)
├── excalidraw-storage-backend/   ← storage API (NestJS + Keyv + Redis)
├── excalidraw-room/              ← Socket.io relay
├── docker-compose.yml
├── excalidraw.sh
└── README.md
```

## Usage

```bash
./excalidraw.sh start      # Start all containers (detached)
./excalidraw.sh stop       # Stop all containers
./excalidraw.sh restart    # Restart without rebuilding
./excalidraw.sh rebuild    # Rebuild images from source and restart
./excalidraw.sh status     # Show container health and ports
./excalidraw.sh logs       # Follow all logs
./excalidraw.sh logs room  # Follow logs for one service
./excalidraw.sh update     # git pull all repos, rebuild, restart
./excalidraw.sh clean      # Remove containers AND delete all data
```

Once started, open **http://localhost:3000**.

## First-time build

The first build takes 5–10 minutes (yarn install + Vite compile). Subsequent builds are faster due to Docker layer caching. Rebuilds after a code change only recompile what changed.

```bash
./excalidraw.sh rebuild
```

## Verifying it works

**Solo drawing:** Open http://localhost:3000 and draw something. It persists in your browser's localStorage.

**Collaboration:**
1. Click the collaboration button (people icon, top right) → Start session
2. Copy the room link and open it in a second browser window (or share with someone on the same network)
3. Draw in one window — it appears in the other in real time
4. Close both windows, reopen the link — your drawing is restored from Redis

**Check service health:**
```bash
./excalidraw.sh status
./excalidraw.sh logs storage   # should show NestJS routes mapped + no errors
./excalidraw.sh logs room      # should show Socket.io server listening
```

## Architecture

```
Browser
  │
  ├─ HTTP → nginx (port 3000)
  │           └─ serves built Excalidraw SPA
  │
  ├─ HTTP → excalidraw-storage (port 8080, internal)
  │           ├─ GET/PUT /api/v2/rooms/:id   (collab scene persistence)
  │           ├─ GET/PUT /api/v2/files/:id   (embedded image storage)
  │           └─ Redis for all storage
  │
  └─ WebSocket → excalidraw-room (port 80, internal)
                  └─ Socket.io relay (real-time cursor/element sync)
```

The frontend's env vars are injected at container startup by `launcher.py` (written into the built HTML as `window._env_`), so the images don't need to be rebuilt to change endpoints.

## What was changed from upstream Excalidraw

Three files were added to `../excalidraw/excalidraw-app/data/`:

- **`StorageBackend.ts`** — interface that both Firebase and HTTP backends implement
- **`httpStorage.ts`** — HTTP implementation (plain fetch calls to the storage service)
- **`config.ts`** — selects backend based on `VITE_APP_STORAGE_BACKEND` env var

`Collab.tsx` and `data/index.ts` were updated to call through the abstraction instead of directly importing Firebase. The original `firebase.ts` is untouched and still present — switching back to Firebase is a one-line env var change (`VITE_APP_STORAGE_BACKEND=firebase`).

## Updating from upstream

When Excalidraw releases updates:

```bash
./excalidraw.sh update
```

This runs `git submodule update --remote --merge` to pull the latest commits from each submodule's tracking branch, then rebuilds. If there are merge conflicts in `Collab.tsx` or `data/index.ts` in the excalidraw submodule, resolve them manually before running `rebuild`.

## Data backup

Redis data lives in the `excalidraw-stack_redis-data` Docker volume. To back it up:

```bash
docker run --rm \
  -v excalidraw-stack_redis-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/redis-backup.tar.gz /data
```

To restore, reverse the tar command before starting the stack.
