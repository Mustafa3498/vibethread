# VibeThread

Real-time fashion e-commerce + behavioral analytics platform.

- **Backend:** Node.js + Express + TypeScript, Prisma (PostgreSQL), Redis, Socket.io
- **Mobile app:** Flutter (BLoC, Dio, secure storage, Socket.io client)
- **Monorepo:** npm workspaces + Turborepo

> Status: backend Steps 1-4 are done (auth, catalog, inventory, realtime).
> The mobile app currently has login + product catalog. See [Roadmap](#roadmap).

---

## What works today

| Area | Details |
|---|---|
| Auth | Register / login / refresh / logout / logout-all / me. Short-lived JWT access token + rotating refresh token in an HttpOnly cookie. Roles: `CUSTOMER`, `SHOPKEEPER`, `ADMIN`. Rate-limited. |
| Catalog | Public product list + detail (ACTIVE products only, no cost price, no exact stock), categories tree, filters, search, sorting, pagination. |
| Staff API | Shopkeeper/Admin product, variant, image, category and inventory management. `costPrice` visible to ADMIN only. |
| Inventory | `available = quantity - reserved`. Stock reservations with TTL (15 min) + background expiry job, guarded single-statement updates (no overselling), DB `CHECK` constraints, stock ledger, low-stock / out-of-stock / fast-moving alerts. |
| Realtime | Socket.io rooms for live stock/price updates per product and staff alerts. |
| Analytics base | Monthly-partitioned `TrackingEvent` table (tracking endpoints come in a later step). |
| Mobile | Login (real, against the API), automatic token refresh, catalog list with search, infinite scroll, pull-to-refresh. |

---

## Project structure

```
vibethread/
├── apps/
│   ├── api/                  # Express API (routes, services, middleware, realtime, jobs)
│   └── mobile/               # Flutter app
│       └── lib/
│           ├── core/         # network (Dio, auth interceptor, cookie jar), services (socket, secure storage)
│           └── features/     # auth, catalog (data / domain / presentation)
├── packages/
│   ├── database/             # Prisma schema, migrations, seed, SQL helpers
│   └── shared/               # shared types, socket event names
├── docker-compose.yml        # Postgres 16 + Redis 7
├── .env.example
└── turbo.json
```

---

## Requirements

This guide is for **Windows 10/11 + WSL2 (Ubuntu)**, the setup this project was built on.

| Tool | Where | Notes |
|---|---|---|
| WSL2 + Ubuntu | Windows | `wsl --install` in PowerShell |
| Docker Engine | **Inside Ubuntu** (no Docker Desktop needed) | `curl -fsSL https://get.docker.com \| sudo sh` |
| Node.js LTS | **Inside Ubuntu**, via nvm | Do NOT use the Windows Node from WSL (see Troubleshooting) |
| Git | Windows and/or Ubuntu | |
| Flutter SDK | **Windows** | Install in a path **without spaces** |
| Android SDK + platform-tools (`adb`) | **Windows** | Install in a path **without spaces**, e.g. `D:\Android\Sdk` |
| Android phone | USB cable | Developer options -> **USB debugging ON** |

Install Node in Ubuntu:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts
which npm        # must be /home/<you>/.nvm/..., NOT /mnt/c/...
```

---

## 1. Backend setup (Ubuntu terminal)

```bash
# 1. Clone
git clone https://github.com/Mustafa3498/vibethread.git
cd vibethread

# 2. Install dependencies
npm install

# 3. Environment file
cp .env.example .env
```

Open `.env` and replace the two JWT secrets with random values:

```bash
sed -i "s|^JWT_ACCESS_SECRET=.*|JWT_ACCESS_SECRET=$(openssl rand -hex 32)|" .env
sed -i "s|^JWT_REFRESH_SECRET=.*|JWT_REFRESH_SECRET=$(openssl rand -hex 32)|" .env
```

```bash
# 4. Start Postgres + Redis
sudo service docker start          # if the Docker daemon is not running
sudo docker compose up -d
sudo docker compose ps             # both should show "healthy"

# 5. Database: generate client, apply migrations, seed
npm run db:generate
npm run db:migrate                 # applies the committed migrations
npm run db:seed

# 6. Run the API (hot reload)
npm run dev
```

Check it (second terminal):

```bash
curl http://localhost:4000/api/health
# {"status":"ok","checks":{"database":true,"redis":true}, ...}

curl "http://localhost:4000/api/products?pageSize=3"
```

### Seeded dev accounts

Password for all: `Password123!` (development only)

| Email | Role |
|---|---|
| `admin@vibethread.dev` | ADMIN |
| `shopkeeper@vibethread.dev` | SHOPKEEPER |
| `customer@vibethread.dev` | CUSTOMER |

The seed also creates a sample product ("Essential Oversized Tee", Black/Olive, S-XL). Size M has only 2 units on purpose, to test "low stock".

---

## 2. Mobile app (Windows PowerShell)

The Flutter app must live in a path **without spaces** (a space in the Windows username broke the native build hooks). If your repo is in a path with spaces, copy `apps/mobile` to e.g. `D:\dev\mobile`:

```powershell
robocopy "C:\path with spaces\vibethread\apps\mobile" D:\dev\mobile /E /XD build .dart_tool .gradle
```

### One-time setup

1. Install Flutter and Android Studio (or the Android command-line tools). Put the SDK somewhere without spaces, set `ANDROID_HOME`, and add `<sdk>\platform-tools` to `PATH`.
2. Check:
   ```powershell
   flutter doctor          # Android toolchain must be [OK]  (Visual Studio is NOT needed for phones)
   adb devices             # your phone must say "device" (accept the USB debugging prompt on the phone)
   ```
3. **Windows port proxy (run ONCE, PowerShell as Administrator).**
   The API port forwarded from WSL can be IPv6-only (`[::1]:4000`), while `adb reverse` connects over IPv4. Without this the app shows *"Unable to reach the server"*.
   ```powershell
   netsh interface portproxy add v4tov6 listenaddress=127.0.0.1 listenport=4000 connectaddress=::1 connectport=4000
   netsh interface portproxy show all
   ```

### Every time you run the app

The backend (section 1) must be running.

```powershell
adb devices
adb reverse tcp:4000 tcp:4000      # re-run after unplugging the cable / restarting adb
cd D:\dev\mobile
flutter pub get
flutter run
```

Sign in with `customer@vibethread.dev` / `Password123!` (prefilled in debug builds).

By default the app talks to `http://localhost:4000` (through `adb reverse`). To use another address (e.g. Wi-Fi):

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000 --dart-define=SOCKET_URL=http://192.168.1.10:4000
```

Do **not** append `/api` to these URLs; the app already calls paths like `/api/auth/login`.

---

## Daily start / stop

**Start**

```bash
# Ubuntu
sudo service docker start
cd ~/vibethread            # your repo path
sudo docker compose up -d
npm run dev
```

```powershell
# PowerShell
adb reverse tcp:4000 tcp:4000
cd D:\dev\mobile
flutter run
```

**Stop:** `Ctrl+C` in both terminals, then optionally `sudo docker compose stop`.
Never run `docker compose down -v` unless you want to **wipe the database**.

**Reset the database completely**

```bash
sudo docker compose down -v && sudo docker compose up -d
npm run db:migrate
npm run db:seed
```

---

## API overview

Base URL: `http://localhost:4000`. Errors look like `{ "error": { "code": "...", "message": "..." } }`.

### Auth (`/api/auth`)

| Method | Path | Notes |
|---|---|---|
| POST | `/register` | Password: 8-72 chars, upper + lower + digit |
| POST | `/login` | Returns `{ user, accessToken }` and sets the `vt_refresh` HttpOnly cookie (path `/api/auth`) |
| POST | `/refresh` | Reads the cookie, rotates it, returns a new `accessToken` |
| POST | `/logout` | Revokes the refresh token |
| POST | `/logout-all` | Requires `Authorization: Bearer <accessToken>` |
| GET | `/me` | Requires Bearer token |

Admin-only routes live under `/api/admin/*`.

### Public catalog (no login)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/categories` | Category tree with `productCount` |
| GET | `/api/categories/:slug` | |
| GET | `/api/products` | `category`, `q`, `minPrice`, `maxPrice`, `color=Black,Olive`, `size=M,L`, `tag`, `weather=hot\|mild\|cold\|rainy\|humid`, `inStock=true`, `sort=newest\|price_asc\|price_desc\|trending`, `page`, `pageSize` (max 48). Returns `{ items, total, page, pageSize, totalPages }` |
| GET | `/api/products/:slug` | Variants with `available`, `inStock`, `lowStock` (never exact quantities or cost) |

### Staff API (`/api/manage/*`, SHOPKEEPER + ADMIN)

| Method | Path | Notes |
|---|---|---|
| POST / PATCH / DELETE | `/categories`, `/categories/:id` | Delete refused while it has products/children |
| GET | `/products`, `/products/:id` | All statuses; `costPrice` only for ADMIN |
| POST | `/products` | Nested `variants` (+ opening `quantity`) and `images` |
| PATCH | `/products/:id` | Price, sale price, promo tag, tags, `status`. ACTIVE needs >= 1 image and >= 1 active variant |
| POST | `/products/:id/archive` \| `/restore` | |
| DELETE | `/products/:id` | ADMIN only; refused if ever ordered |
| POST | `/products/:id/variants` | |
| PATCH | `/variants/:variantId` | `priceOverride`, `colorHex`, `isActive`, `lowStockThreshold` |
| POST / PUT / DELETE | `/products/:id/images`, `/images/order`, `/images/:imageId` | URLs only for now |
| GET | `/inventory` | `q`, `lowStock=true`, `outOfStock=true` |
| PATCH | `/inventory/:variantId` | `{ "delta": 5 }` or `{ "setQuantity": 20 }` + optional `reason` |
| GET | `/inventory-movements` | Stock ledger |
| GET / PATCH / POST | `/alerts`, `/alerts/:id/read`, `/alerts/read-all` | |

### Realtime (Socket.io)

The client connects with `auth: { token: <accessToken> }`.

| Event | Direction | Room | Payload |
|---|---|---|---|
| `product:watch` / `product:unwatch` | client -> server | | `productId` (max 20 watched) |
| `stock:updated` | server -> | `product:<id>` | `{ productId, variantId, available, lowStock }` |
| `stock:updated` | server -> | `staff` | plus `sku, color, size, quantity, reserved, lowStockThreshold` |
| `product:updated` | server -> | `product:<id>` | price / promo / status change |
| `inventory:alert` | server -> | `staff` | alert details |

---

## Useful commands

| Command | What it does |
|---|---|
| `npm run dev` | Build packages and start the API with hot reload |
| `npm run db:generate` | Generate the Prisma client |
| `npm run db:migrate` | Apply migrations (creates a new one if the schema changed) |
| `npm run db:seed` | Seed dev data (idempotent) |
| `npm run db:studio` | Browse the database in the browser |
| `npm run typecheck` | Type-check all packages |
| `npm run smoke:auth -w @vibethread/api` | Auth smoke test (API must be running) |
| `npm run smoke:catalog -w @vibethread/api` | Catalog + sockets smoke test (API must be running) |
| `npm run smoke:inventory -w @vibethread/api` | Inventory engine test incl. the 20-buyer oversell race |

### Changing the database schema

```bash
# edit packages/database/prisma/schema.prisma, then:
npm run db:migrate
```

The `TrackingEvent` table is **partitioned by month** (raw SQL in `packages/database/prisma/sql/events_partitioning.sql`, already included in the first migration). Partitions exist for 2026-10 to 2026-12 plus a default partition; add new months before they are needed.

If `db:migrate` asks for a new migration name on a fresh clone, something has drifted: press `Ctrl+C` and ask before continuing.

---

## Troubleshooting

**`P1000: Authentication failed against database server`**
Usually `npm`/`npx` is the **Windows** one running inside WSL. Check `which npm`. If it prints `/mnt/c/...`, install Node with nvm inside Ubuntu (see Requirements). Also verify nothing else listens on port 5432.

**`npm run ...` fails with Windows batch errors / `docker` not found**
Same cause: Windows npm. Fix with nvm as above.

**`permission denied` for docker**
Use `sudo docker ...`, or `sudo usermod -aG docker $USER` and reopen the terminal. Note: the `npm run infra:*` scripts call `docker` without `sudo`.

**`Invalid environment variables: JWT_ACCESS_SECRET Required`**
Your `.env` is missing the JWT secrets (see step 3).

**Git shows every file as modified (Windows drive)**
Line endings. Run `git config core.autocrlf input` and `git config core.filemode false`.

**Flutter: `Unable to locate Android SDK`**
`flutter config --android-sdk "D:\Android\Sdk"` and set `ANDROID_HOME`.

**Flutter build: `'C:\Users\First' is not recognized` / native assets hook failed**
A space in a path (username, project, pub cache, or Flutter SDK). Move the project to e.g. `D:\dev\mobile` and set `PUB_CACHE=D:\pub-cache` (`setx PUB_CACHE "D:\pub-cache"`, then reopen PowerShell).

**Flutter build: `Android sdkmanager did not install NDK ...`**
Install the NDK version named in the error with the SDK Manager (Android Studio -> SDK Tools -> Show Package Details -> NDK (Side by side)).

**`adb devices` shows `unauthorized`**
Unlock the phone and accept "Allow USB debugging". If no prompt: `adb kill-server`, `adb start-server`, reconnect, or revoke USB debugging authorizations in Developer options.

**App says "Unable to reach the server" / "Connection closed before full header was received"**
1. Is the API running? `curl http://localhost:4000/api/health` in Ubuntu.
2. `adb reverse --list` must show `tcp:4000`. Re-run `adb reverse tcp:4000 tcp:4000`.
3. Run the **port proxy** command from section 2 (as Administrator), then test `Invoke-RestMethod http://127.0.0.1:4000/api/health` in PowerShell.
4. Open `http://localhost:4000/api/health` in the phone's browser: if it shows JSON, the tunnel works.

**Windows cannot reach the WSL backend at all**
`wsl --shutdown`, reopen Ubuntu, then start Docker and `npm run dev` again.

---

## Roadmap

- [x] Step 1-2: monorepo, Docker, Prisma schema, partitioned events table, health check
- [x] Step 3: auth (JWT + rotating refresh cookie), roles
- [x] Step 4: catalog, inventory, reservations, alerts, realtime stock
- [ ] Mobile: product detail (color/size selector, live stock), cart, checkout
- [ ] Step 5: behavioral tracking events API (hover, zoom, size toggle, ...)
- [ ] Step 7: cart + orders (uses the reservation engine)
- [ ] Shopkeeper and owner/admin dashboards
- [ ] Image upload (cloud storage), analytics aggregates (`ProductDailyStats`)

---

## Security notes

- Seeded passwords and the `.env.example` secrets are for **development only**. Never reuse them.
- Never commit `.env`. It is git-ignored.
- In production set `NODE_ENV=production` (the refresh cookie becomes `Secure`) and serve the API over HTTPS. The Android `usesCleartextTraffic` flag in `AndroidManifest.xml` is for local development only; remove it for release builds.
