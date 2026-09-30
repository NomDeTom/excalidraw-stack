# Excalidraw — Self-Hosted Stack

A self-contained Excalidraw deployment with no dependency on Firebase, Google or any other
outside service. It is the desktop counterpart of the Excalidraw app on the
[Irate-Box](https://github.com/NomDeTom/irate-box) hub: the same fork, the same storage API.

## What's included

| Service | Built from | Role |
|---|---|---|
| `excalidraw` | `excalidraw/` (fork) | The app, served by nginx on port 3000. nginx also proxies `/api/v2/` and `/socket.io/`, so the browser only ever talks to this one origin |
| `room` | `excalidraw-room/` (fork) | socket.io relay for live collaboration. Rooms live in memory; no database |
| `storage` | `excalidraw-storage-backend/` | Legacy modes only: NestJS over Keyv, with Redis or SQLite behind it |
| `redis` | `redis:7-alpine` | `full` mode only |

## Storage modes

```bash
./excalidraw.sh start                  # hub mode (the default)
./excalidraw.sh --mode full start      # remembered in .stack-mode for later commands
```

| Mode | Storage | Notes |
|---|---|---|
| **`hub`** (default) | The Irate-Box hub's `store.py`, running on this machine | Start it first: `python3 server.py` in `~/irate-box` (port 8000). nginx reaches it at `host.docker.internal:8000`. No NestJS, no Redis, nothing to back up but the hub's `store/` directory |
| `full` (legacy) | NestJS + Redis | The original stack. Data in the `excalidraw-stack_redis-data` volume |
| `sqlite` (legacy) | NestJS over a SQLite file | Untested. Data in the `excalidraw-stack_sqlite-data` volume |

`store.py` implements the same six-endpoint `/api/v2` contract as the NestJS backend, so the
app cannot tell the modes apart. The legacy modes stay while hub mode is being proven; the
plan is to retire them (`notes-sync/irate-box/plans/offline-storage-plan.md`).

## Requirements

- Docker with Compose (Docker Desktop with WSL 2 integration, on Windows)
- Git, for the submodules
- For `hub` mode: a checkout of `irate-box` and Python 3

```bash
git clone --recurse-submodules https://github.com/nomdetom/excalidraw-stack
cd excalidraw-stack
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
./excalidraw.sh mode       # Print the current mode
./excalidraw.sh update     # git pull all repos, rebuild, restart
./excalidraw.sh clean      # Remove containers AND delete all data volumes
```

Once started, open **http://localhost:3000**. The first build takes 5–10 minutes (yarn install
and the Vite compile); later builds reuse Docker's layer cache.

## Architecture

```
Browser ── http://localhost:3000 ── nginx (excalidraw container)
                                      ├─ /            the built app
                                      ├─ /api/v2/*    → store.py on the host   (hub)
                                      │               → storage:8080           (full, sqlite)
                                      └─ /socket.io/* → room:80                (live collaboration)
```

The app is configured with relative URLs: `VITE_APP_HTTP_STORAGE_BACKEND_URL=/api/v2`, and an
empty `VITE_APP_WS_SERVER_URL`, which socket.io takes to mean "this origin". `launcher.py`
writes those values into the built HTML at container start (`window._env_`), so switching
mode never needs a rebuild. The per-mode nginx configs are in `nginx/`.

> Before 2026-10-01 the browser was handed `http://room:80` and `http://storage:8080`,
> hostnames that only resolve inside Docker's network, with only port 3000 published.
> Collaboration and server-side storage could not have worked from a browser in that setup.

## Verifying it works

**Solo drawing:** open http://localhost:3000 and draw. It persists in the browser's localStorage.

**Shareable link:** menu → Export → "Export to link". The scene is stored through `/api/v2`;
open the link in a private window.

**Collaboration, without a browser:** `cd tests && npm install && node collab-smoke.mjs http://localhost:3000`
(or a hub's address). Two clients join a room through `/socket.io/`; one broadcasts and the
other must receive it. Run it after every submodule bump.

**Collaboration:** the people icon (top right) → Start session. Open the room link in a second
window and draw in one; it appears in the other. Close both and reopen the link: the drawing
comes back from storage.

## The forks

- **`excalidraw/`** — upstream Excalidraw plus: a pluggable storage backend (Firebase or plain
  HTTP), `.env.hub` and `yarn build:hub` for the Irate-Box hub (offline: no Excalidraw+, AI,
  social, library or analytics surfaces, fonts served locally, hub-gallery saves, collaboration
  enabled only when a relay answers), and `Dockerfile.standalone` + `launcher.py` for this stack.
  Rebased onto upstream on 2026-10-01.
- **`excalidraw-room/`** — upstream relay plus a Node 24 base image and a `HOST` variable to bind
  one address (the hub runs it on `127.0.0.1` behind Caddy).
- **`excalidraw-storage-backend/`** — upstream plus a Node 24 base image. Legacy modes only.

## Updating from upstream

```bash
./excalidraw.sh update
```

This runs `git submodule update --remote --merge` and rebuilds. The Excalidraw fork carries
patches to `Collab.tsx`, `App.tsx` and `data/index.ts`; resolve any conflicts there before
`rebuild`. Rebasing the fork itself onto upstream about monthly keeps those conflicts small.

## Data backup

- **hub:** the hub's state directory (`store/` in the irate-box checkout, or `/var/lib/hub/store`
  on a board).
- **full:** the `excalidraw-stack_redis-data` volume:
  ```bash
  docker run --rm -v excalidraw-stack_redis-data:/data -v "$(pwd)":/backup \
    alpine tar czf /backup/redis-backup.tar.gz /data
  ```
- **sqlite:** the `excalidraw-stack_sqlite-data` volume, the same way.
