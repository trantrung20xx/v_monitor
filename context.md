# v_monitor — Full Source Context

> Enterprise device monitoring system (UAV controllers, vehicles) with real-time GPS tracking, journey history replay, and reverse geocoding. **Flutter** frontend + **FastAPI** backend + **PostgreSQL/PostGIS** database + **MQTT** telemetry ingestion.

---

## 1. Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────┐
│                          MQTT Broker                                  │
│  (topic: v_monitor/telemetry/{device_code})                          │
└─────────────┬─────────────────────────────────────────────────────────┘
              │ paho-mqtt (thread-safe, async bridge)
              ▼
┌─────────────────────────────────────────────────┐
│  FastAPI Backend  (Python 3.12+, async)         │
│  ┌──────────┐ ┌────────────┐ ┌───────────────┐ │
│  │ REST API │ │  WebSocket │ │  MQTT Service │ │
│  │ /api/v1  │ │  /api/v1/ws│ │  (subscriber) │ │
│  └────┬─────┘ └─────┬──────┘ └───────┬───────┘ │
│       │             │                │          │
│  ┌────▼─────────────▼────────────────▼────────┐ │
│  │        Service Layer (business logic)       │ │
│  │  DeviceService · TrackingService ·          │ │
│  │  GeocodingService · RealtimeService         │ │
│  └────────────────────┬───────────────────────┘ │
│                       │ SQLAlchemy 2.0 Async     │
│  ┌────────────────────▼───────────────────────┐ │
│  │  PostgreSQL + PostGIS (asyncpg)            │ │
│  │  7 tables · UUID PKs · SRID 4326          │ │
│  └────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
              │ REST + WebSocket
              ▼
┌─────────────────────────────────────────────────┐
│  Flutter Frontend  (Dart 3.12+, cross-platform) │
│  Material 3 · flutter_bloc (Cubit) · go_router  │
│  flutter_map (OSM/Google Satellite tiles)        │
│  4 features: Dashboard, Map, DeviceDetail,       │
│              JourneyHistory (with replay engine)  │
└─────────────────────────────────────────────────┘
```

### Tech Stack

| Layer | Technology | Key Libraries |
|-------|-----------|---------------|
| Frontend | Flutter/Dart 3.12+ | flutter_bloc 9.x, go_router 15.x, flutter_map 7.x, latlong2, dio 5.x, web_socket_channel, google_fonts (Inter), equatable, intl, device_preview |
| Backend | Python 3.12+ / FastAPI | SQLAlchemy 2.0 (async), asyncpg, paho-mqtt, pydantic 2.x, pydantic-settings, GeoAlchemy2, Alembic, websockets |
| Database | PostgreSQL + PostGIS | Geography(POINT, SRID=4326), UUID PKs, JSONB, TIMESTAMP(tz), composite indexes |
| Messaging | MQTT | Topics: `v_monitor/telemetry/{device_code}` |
| Geocoding | Nominatim (OSM) | Reverse geocoding with in-memory cache |

---

## 2. Database Schema (7 Tables)

### 2.1 `devices`
Primary device registry. Fields: `id` (UUID PK), `device_code` (unique, indexed), `name`, `device_type` (enum: UAV_CONTROLLER, VEHICLE, OTHER), `serial_number`, `manufacturer`, `model`, `firmware_version`, `status` (enum: UNKNOWN, OFFLINE, ONLINE, ACTIVE, INACTIVE, MAINTENANCE, RETIRED), `metadata_json` (JSONB), `created_at`, `updated_at`. Has one-to-one relationship with `device_latest_state`.

### 2.2 `device_latest_state`
Latest telemetry snapshot per device (1:1 with devices). PK = `device_id` (FK → devices.id, CASCADE). Fields: `last_seen_at`, `is_online`, `current_latitude`, `current_longitude`, `current_speed_mps`, `current_heading_deg`, `created_at`, `updated_at`.

### 2.3 `location_samples`
Historical GPS data points (append-only, high-volume). Fields: `id` (UUID PK), `device_id` (FK), `measured_at` (TIMESTAMP TZ, indexed), `received_at`, `latitude`, `longitude`, `location` (PostGIS Geography POINT SRID 4326, indexed), `altitude_m`, `speed_mps`, `heading_deg`, `accuracy_m`, `satellite_count`, `source`, `source_message_id` (FK → telemetry_messages), `created_at`. Composite index: `(device_id, measured_at)`.

### 2.4 `telemetry_messages`
Raw MQTT message archive. Fields: `id` (UUID PK), `device_id` (FK), `received_at`, `measured_at`, `message_type`, `payload` (JSONB), `processing_status` (enum: PENDING, PROCESSED, FAILED, SKIPPED), `processing_error`, `created_at`.

### 2.5 `device_events`
Auto-detected state-change events. Fields: `id` (UUID PK), `device_id` (FK, indexed), `event_type` (string, indexed — ONLINE, OFFLINE, MOVEMENT_STARTED, MOVEMENT_STOPPED, GPS_LOST, GPS_RESTORED, GEOFENCE_EXIT, STATUS_CHANGE, ERROR), `occurred_at` (indexed), `location` (PostGIS Geography POINT), `metadata` (JSONB with source, description, speed_mps, etc.).

### 2.6 `usage_sessions`
Device operation sessions with aggregated metrics. Fields: `id`, `device_id` (FK, indexed), `started_at` (indexed), `ended_at`, `start_location`/`end_location` (PostGIS POINT), `distance_m`, `avg_speed_mps`, `max_speed_mps`, `moving_duration_s`, `stopped_duration_s`, `route_geometry` (PostGIS LINESTRING), `status` (enum: ACTIVE, COMPLETED, CANCELLED, UNKNOWN), `end_reason`, `created_at`, `updated_at`.

### 2.7 `audit_logs`
Operation audit trail. Fields: `id`, `actor_id`, `action`, `entity_type`, `entity_id`, `occurred_at` (indexed), `old_value` (JSONB), `new_value` (JSONB), `metadata` (JSONB), `created_at`.

### Mixins
- `UUIDMixin`: UUID v4 primary key.
- `TimestampMixin`: `created_at` (UTC default), `updated_at` (UTC default, auto-update).

---

## 3. Backend API (FastAPI)

### 3.1 Configuration (`backend/app/core/config.py`)
`Settings` class via `pydantic_settings.BaseSettings`, loaded from `backend/.env`. Key settings: `database_url` (required), `api_prefix` (/api/v1), `mqtt_*` (host/port/auth/tls), `geocoding_*` (Nominatim), `tracking_gap_threshold_seconds` (300), `tracking_outlier_speed_kmh` (500), `tracking_max_history_samples` (100000), `jwt_secret`, `cors_origins`. Singleton via `@lru_cache`.

### 3.2 Database (`backend/app/core/database.py`)
Async SQLAlchemy engine (`asyncpg`), connection pool (20+10 overflow, recycle 30min). `get_db()` async generator for FastAPI dependency injection.

### 3.3 REST Endpoints

**Devices** (`/api/v1/devices`)
- `GET /` → `List[DeviceResponse]` — All devices with latest_state (eager loaded via selectinload).
- `POST /` → `DeviceResponse` — Create device + initialize DeviceLatestState.
- `GET /{device_id}` → `DeviceResponse` — Single device by UUID.

**Tracking** (`/api/v1/tracking`)
- `POST /` → `LocationSampleResponse` — Add GPS point, auto-detect events (ONLINE, MOVEMENT_STARTED/STOPPED), update latest_state, broadcast via WebSocket.
- `GET /{device_id}/history?limit=100` → `List[LocationSampleResponse]` — Recent N samples (DESC).
- `GET /{device_id}/history/range?from=&to=&max_samples=` → `LocationHistoryResponse` — Time-range query (ASC by measured_at, id). Returns `{samples, total_count, truncated}`.
- `GET /{device_id}/events?limit=100&event_type=` → `List[DeviceEventResponse]` — Event timeline. Accepts UUID or device_code.

**Geocoding** (`/api/v1/geocoding`)
- `GET /reverse?latitude=&longitude=` → `ReverseGeocodeResponse` — Nominatim reverse geocode with in-memory cache (key: lat/lng rounded to 5 decimals). Smart address formatting (Vietnamese locale priority).

**WebSocket** (`/api/v1/ws`)
- Full-duplex. Server broadcasts: `DEVICE_UPDATE` (device JSON), `DEVICE_EVENT` (event JSON). Client sends: `PING` → server replies `PONG`.

### 3.4 MQTT Service (`backend/app/services/mqtt_service.py`)
Singleton `MQTTService` using paho-mqtt (compatible v1.x & v2.x). Subscribes to `v_monitor/telemetry/#` (QoS 1). Message processing pipeline:
1. Parse JSON payload → extract device_code from topic path.
2. Resolve device_code → device_id (DB lookup).
3. Create `LocationSampleCreate` with WKT point.
4. Call `TrackingService.add_location()` → auto-detect events.
5. Broadcast updated device + events via WebSocket.

**MQTT Payload Format:**
```json
{
  "latitude": 21.0285, "longitude": 105.8048,
  "altitude_m": 36.5, "speed_mps": 12.5,
  "heading_deg": 45.0, "measured_at": "ISO8601"
}
```

### 3.5 Event Detection Logic (`TrackingService.add_location`)
- **ONLINE**: Generated when `is_online` was false, device sends new location.
- **MOVEMENT_STARTED**: Previous speed ≤ 0.5 m/s → new speed > 0.5 m/s.
- **MOVEMENT_STOPPED**: Previous speed > 0.5 m/s → new speed ≤ 0.5 m/s.
- All events stored in `device_events` and broadcast via WebSocket in real-time.

### 3.6 Realtime Service
Simple WebSocket connection manager. Maintains `active_connections` list. `broadcast_telemetry()` sends JSON to all connected clients, auto-cleans stale connections on error.

---

## 4. Frontend Architecture (Flutter)

### 4.1 Project Structure
```
lib/
├── main.dart                          # Entry point, creates ApiClient + WebsocketClient
├── app/
│   ├── app.dart                       # VMonitorApp root widget, MultiRepositoryProvider
│   ├── app_router.dart                # GoRouter config with ShellRoute navigation
│   └── app_theme.dart                 # Material 3 theme (Inter font, blue seed #1677FF)
├── core/
│   ├── config/
│   │   ├── app_config.dart            # Compile-time env vars (API_BASE_URL, WS_BASE_URL, etc.)
│   │   └── map_tile_providers.dart    # OSM street + Google Hybrid satellite tile URLs
│   ├── constants.dart                 # ApiConstants, AppConstants (movingThreshold=0.5 m/s)
│   ├── network/
│   │   ├── api_client.dart            # Dio HTTP client wrapper
│   │   └── websocket_client.dart      # WebSocket with auto-reconnect + heartbeat (PING/PONG)
│   ├── utils/
│   │   ├── device_formatters.dart     # Display formatting (speed km/h, heading, coordinates, relative time, Vietnamese labels)
│   │   └── map_launcher_service.dart  # Open Google Maps / Apple Maps / copy location URL
│   └── widgets/
│       ├── device_icon.dart           # Icon by device type (gamepad=UAV, car=VEHICLE)
│       ├── stat_card.dart             # Dashboard statistics card
│       └── status_badge.dart          # Colored status badge (online/offline/moving)
├── data/
│   ├── models/
│   │   ├── device_model.dart          # DeviceModel (JSON deserialization from API)
│   │   ├── device_event_model.dart    # DeviceEventModel (with eventLabel, category)
│   │   ├── location_model.dart        # LocationModel (GPS sample)
│   │   ├── location_history_response.dart  # Wrapper for range query response
│   │   └── reverse_geocode_model.dart # ReverseGeocodeModel (bestAddress getter)
│   └── repositories/
│       ├── device_repository.dart     # HTTP + WebSocket stream (deviceUpdates, deviceEvents)
│       ├── tracking_repository.dart   # Location history + events HTTP
│       └── geocoding_repository.dart  # Reverse geocode with dual-layer cache + dedup
├── domain/entities/
│   ├── device_query_filter.dart       # Client-side device list filtering (all/online/offline/moving/stopped/stale)
│   ├── device_status_resolver.dart    # Multi-dimensional status resolution (connectivity × freshness × movement × activity)
│   ├── gps_validator.dart             # Coordinate validation, outlier/teleport detection, bearing/distance/interpolation
│   └── route_segment.dart            # Splits GPS history into continuous segments by gap threshold
└── features/
    ├── dashboard/                     # Dashboard feature
    ├── map/                           # Full-screen map view
    ├── device_detail/                 # Device detail page
    └── journey_history/               # Journey history replay
```

### 4.2 State Management: flutter_bloc (Cubit pattern)
All features use `Cubit<State>` with `Equatable` states and `copyWith()`.

### 4.3 Routing (go_router)
```
/              → DashboardPage (ShellRoute with nav rail/bottom nav)
/map           → MapViewPage (ShellRoute)
/devices/:id   → DeviceDetailPage (root navigator, full screen)
```
`_AppShell`: Responsive — desktop (≥800px) uses `NavigationRail` (88px sidebar), mobile uses `NavigationBar`. Custom `_DesktopNavRail` with app logo, 2 destinations (Dashboard, Bản đồ).

### 4.4 Theme & UI Design (`app_theme.dart`)
- **Design system**: Material 3 with `ColorScheme.fromSeed(#1677FF)`.
- **Font**: Google Fonts Inter.
- **Scaffold bg**: Light `#F4F6F8`, Dark `#121212`.
- **Cards**: Rounded 8px, 1px border (`#E2E8F0` light), subtle shadow.
- **Color conventions**: Active blue `#1677FF`, inactive `#66727D`, border `#E4E9ED`.
- Both light and dark theme defined. Currently defaults to light.
- Vietnamese language throughout UI labels.

### 4.5 Network Layer

**ApiClient**: Dio wrapper. Base URL from `AppConfig.apiBaseUrl` (compile-time env). Debug mode adds `LogInterceptor`. Methods: `get()`, `post()`.

**WebsocketClient**: Full lifecycle management.
- Auto-reconnect on disconnect (5s delay).
- Heartbeat PING every 25s.
- `messages` stream (broadcast `StreamController<Map<String, dynamic>>`).
- Factory pattern for testability (`WebSocketChannelFactory`).

### 4.6 Configuration (`AppConfig`)
Compile-time `String.fromEnvironment` / `int.fromEnvironment` / `bool.fromEnvironment`. Defaults:
- `API_BASE_URL` = `http://127.0.0.1:8000/api/v1`
- `WS_BASE_URL` = `ws://127.0.0.1:8000`
- `WS_PATH` = `/api/v1/ws`
- `CONNECT_TIMEOUT_SECONDS` = 10
- `ENABLE_DEVICE_PREVIEW` = false

Config JSON files in `config/` (development.json, production.json, cloudflare.json) for different environments.

---

## 5. Features in Detail

### 5.1 Dashboard (`features/dashboard/`)

**DashboardCubit** — Loads all devices, subscribes to WebSocket `DEVICE_UPDATE` stream, computes live statistics, resolves addresses.

**DashboardState** — `{isLoading, error, devices[], totalDevices, onlineCount, offlineCount, movingCount, stoppedCount, inactiveCount, staleCount, attentionCount, searchQuery, statusFilter, deviceAddresses{}}`.

**DashboardPage** (30KB) — Main monitoring dashboard:
- **Stats overview bar**: StatCards showing total/online/offline/moving/stopped/stale counts.
- **Device list panel**: Searchable, filterable list. Filters: All, Online, Offline, Moving, Stopped, Stale GPS.
- **Device cards**: Show device name, type icon, status badge, speed, heading, address, last seen relative time.
- Navigation to `/devices/:id` on card tap.

**Key widgets:**
- `StatsOverview` — Row/Wrap of StatCards
- `DeviceListPanel` — Search bar + filter chips + scrollable DeviceCard list
- `DeviceCard` — Rich device summary card with status, location, speed

### 5.2 Live Map (`features/map/`)

**MapViewPage** (25KB) — Full-screen interactive map with all device markers:
- Uses `flutter_map` with OSM street / Google Hybrid satellite tile switching.
- Map type toggle button (standard ↔ satellite).
- `DeviceListOverlay` — Floating collapsible panel listing devices with search and filter (same as dashboard filter).
- Device markers on map with bearing rotation icons.
- Tap marker → show device info popup with navigate to detail action.
- Auto-centers/fits all device positions on load.

### 5.3 Device Detail (`features/device_detail/`)

**DeviceDetailCubit** — Loads device info + events + location history for selected time range. Subscribes to realtime device updates + events (WebSocket). Resolves reverse geocode address with caching.

**DeviceDetailState** — `{isLoading, isRangeLoading, timeRange (today/yesterday/24h/7d/custom), rangeFrom, rangeTo, error, device, events[], locations[], address}`.

**DeviceDetailPage** (224KB — largest file) — Comprehensive device dashboard:
- **Header**: Device name, code, type, manufacturer/model, status badge, coordinates.
- **Live map section**: Current device position on interactive map, Google Maps link.
- **Stats cards**: Online status, speed, heading, GPS freshness, address.
- **Event timeline**: Chronological list of device events with category-based icons and Vietnamese labels.
- **Location history overview**: Time-range selectable (today/yesterday/24h/7d/custom), shows location path on mini-map.
- **Navigation to Journey History** page for full replay.

**Time Range Support**: `OverviewTimeRange` enum — today, yesterday, last24h, last7d, custom. Switching triggers re-fetch of location data.

### 5.4 Journey History (`features/journey_history/`)

**JourneyHistoryCubit** — Full replay engine for GPS history. Core capabilities:
1. **Load**: Fetch GPS samples for time range → GpsValidator.sanitizeSamples() → RouteSegment.splitIntoSegments().
2. **Replay engine**: Timer-based playback at 30fps (33ms interval). Supports play/pause/resume/reset/seek.
3. **Interpolation**: Linear interpolation between GPS points for smooth marker movement.
4. **Gap handling**: Skips over time gaps > gapThreshold (default 5 min).
5. **Playback speed**: 0.5x, 1x, 2x, 4x, 8x, 16x.
6. **Race condition protection**: Query versioning (`_queryVersion`) prevents stale response overwrites.

**JourneyHistoryState** — `{status (idle/loading/ready/playing/paused/completed/error), selectedDevice, fromTime, toTime, rawSamples[], validSamples[], segments[], totalCount, truncated, totalDistanceM, movingDurationS, stoppedDurationS, maxSpeedMps, avgSpeedMps, gapThreshold, currentReplayTime, currentPosition (LatLng), currentSpeedMps, currentHeadingDeg, currentSampleIndex, playbackSpeed, followCamera, selectedPoint}`.

Computed properties: `playbackProgress` (0.0–1.0), `currentDistanceM`, `hasRoute`, `isEmpty`.

**JourneyHistoryPage** (24KB) — Journey history viewer:
- Time selector (preset ranges + custom date-time picker).
- Route summary band (distance, moving time, stopped time, max speed, avg speed).
- Playback controls (play/pause/reset, speed selector, step forward/backward 30s, progress slider, follow camera toggle).
- Full-screen map with route polylines and animated device marker.

**Journey History Widgets** (7 files):
- `HistoryTimeSelector` — Date/time range picker with presets.
- `PlaybackControls` — Transport controls, speed selector, progress slider.
- `RouteSummaryBand` — Compact route statistics.
- `HistoryMapLayers` (34KB) — Map rendering: route polylines (colored per segment), start/end markers, GPS point markers, animated device marker (rotated by heading), point info popup on tap.
- `PointInfoPopup` — Shows GPS point details (time, speed, heading, coordinates, altitude, accuracy, satellite count).
- `CustomDateTimeRangeDialog` — Custom from/to datetime picker.
- `CustomGapDialog` — Configure gap threshold (minutes/seconds input).

---

## 6. Domain Logic

### 6.1 Device Status Resolution (`DeviceStatusResolver`)
Multi-dimensional status computed from raw data:

| Dimension | Values | Logic |
|-----------|--------|-------|
| Connectivity | online, offline | `is_online && lastSeenAge ≤ 5min` |
| Freshness | fresh, stale, unknown | `lastSeenAge ≤ 2min → fresh, else stale` |
| Movement | moving, stopped, unknown | Only computed when online+fresh. `speed > 0.5 m/s → moving` |
| Activity | active, inactive, unknown | Based on `baseStatus` field from DB |

Label priority: offline → stale GPS → moving → stopped → online → inactive.
Color mapping: grey (offline), redAccent (stale), blue (moving), orange (stopped), green (online).

Configurable thresholds via `DeviceStateThresholds`: onlineTimeout (5min), gpsStaleTimeout (2min), movementSpeedThreshold (0.5 m/s).

### 6.2 GPS Validator (`GpsValidator`)
- `isValidCoordinate()`: Checks bounds (-90..90, -180..180), rejects NaN/Infinity/null/(0,0) (Null Island).
- `sanitizeSamples()`: Sorts by time → filters invalid coords → detects teleport outliers (implied speed > 500 km/h in < 5 min) → spike detection (if next point returns to normal, drop the spike).
- `calculateBearing()`: Spherical bearing (0°=N, 90°=E, 180°=S, 270°=W).
- `calculateDistanceM()`: Haversine distance via latlong2.
- `interpolatePosition()`: Linear lat/lng interpolation by ratio t (0.0–1.0).

### 6.3 Route Segment (`RouteSegment`)
Splits sorted GPS samples into continuous segments where inter-point time gaps ≤ gapThreshold (default 5 min). Each segment computes: `distanceM`, `movingDurationS`, `stoppedDurationS`, `maxSpeedMps`, `avgSpeedMps`. Movement detection per pair: speed > 0.5 m/s or implied speed from distance/time > 0.5 m/s.

### 6.4 Device Query Filter (`DeviceQueryFilter`)
Client-side filtering: text search (name, code, type) + status filter (all/online/offline/moving/stopped/stale). Uses `DeviceStatusResolver` for accurate filtering.

---

## 7. Data Flow Diagrams

### 7.1 Telemetry Ingestion (MQTT → DB → WebSocket → UI)
```
Device → MQTT Broker → MQTTService.on_message()
  → process_message(): parse JSON, resolve device_code → device_id
    → TrackingService.add_location():
       1. Create LocationSample (with PostGIS WKT point)
       2. Detect events (ONLINE / MOVEMENT_STARTED / MOVEMENT_STOPPED)
       3. Update DeviceLatestState
       4. Commit transaction
    → DeviceService.get_device() → serialize DeviceResponse
    → RealtimeService.broadcast_telemetry({type: DEVICE_UPDATE, device: {...}})
    → RealtimeService.broadcast_telemetry({type: DEVICE_EVENT, event: {...}})
                        ↓ WebSocket
Flutter WebsocketClient.messages stream
  → DeviceRepository.deviceUpdates / deviceEvents
    → DashboardCubit._onDeviceUpdated()  → UI refresh
    → DeviceDetailCubit._onDeviceUpdated() → UI refresh
```

### 7.2 Journey History Replay
```
User selects device + time range → JourneyHistoryCubit.loadHistory()
  → TrackingRepository.getLocationHistoryRange() → GET /tracking/{id}/history/range
  → Backend: SELECT location_samples WHERE device_id AND measured_at BETWEEN from AND to ORDER BY ASC
  → Response: {samples[], total_count, truncated}
  → GpsValidator.sanitizeSamples() → filter invalid/outlier points
  → RouteSegment.splitIntoSegments() → split by gap threshold
  → Compute aggregates (distance, moving/stopped duration, speeds)
  → Emit JourneyHistoryState(ready)

User presses Play → Timer.periodic(33ms) at 30fps
  → Each tick: advance currentReplayTime by (realDelta × playbackSpeed)
  → Find bracketing samples → linear interpolate position
  → Skip gaps > gapThreshold automatically
  → Emit state with updated position/heading/speed/time
  → Map animates marker movement + camera follow
```

---

## 8. File Size Reference

| File | Size | Purpose |
|------|------|---------|
| `device_detail_page.dart` | 224 KB | Largest UI file, comprehensive device dashboard |
| `history_map_layers.dart` | 34 KB | Journey map rendering with route polylines + markers |
| `dashboard_page.dart` | 30 KB | Main dashboard UI |
| `map_view_page.dart` | 25 KB | Full-screen live map |
| `device_list_overlay.dart` | 25 KB | Floating device list on map |
| `journey_history_page.dart` | 24 KB | Journey replay page |
| `journey_history_cubit.dart` | 14 KB | Replay engine logic |
| `device_card.dart` | 14 KB | Device card widget |
| `custom_gap_dialog.dart` | 14 KB | Gap threshold config dialog |
| `history_time_selector.dart` | 14 KB | Time range selector widget |

---

## 9. Key Design Decisions & Patterns

1. **Clean Architecture (modified)**: `data/` (models, repositories) → `domain/` (entities, business logic) → `features/` (UI + Cubit). No abstract repository interfaces; repositories use concrete `ApiClient`.

2. **Cubit over Bloc**: Simpler state management without event classes. States use `Equatable` + `copyWith()`.

3. **Repository pattern**: Repositories encapsulate HTTP calls (via Dio `ApiClient`) and WebSocket streams. They handle JSON deserialization and error logging.

4. **Real-time via WebSocket**: Server pushes `DEVICE_UPDATE` and `DEVICE_EVENT` messages. Client filters stream per-device in Cubits. Heartbeat PING/PONG keeps connection alive.

5. **Dual geocoding cache**: Backend `GeocodingService` caches by coordinate key (5 decimals). Frontend `GeocodingRepository` also caches + deduplicates concurrent requests for same coordinate.

6. **GPS data pipeline**: Raw → validate coordinates → detect teleport outliers → split into time-continuous segments → compute aggregates. All processing is client-side after API fetch.

7. **Responsive shell**: Desktop (≥800px) gets NavigationRail sidebar; mobile gets BottomNavigationBar. DeviceDetail is full-screen (outside shell).

8. **Vietnamese localization**: All UI labels, status texts, error messages, event descriptions in Vietnamese. Backend comments also in Vietnamese.

9. **Compile-time configuration**: Flutter uses `--dart-define` for env vars. Backend uses `.env` + `pydantic-settings`.

10. **PostGIS spatial data**: Location stored both as scalar (latitude/longitude floats) for easy API serialization AND as PostGIS Geography POINT for future spatial queries (proximity, geofencing).

---

## 10. Development & Deployment

### Run Backend
```bash
cd backend
pip install -r requirements.txt
# Create .env from .env.example with your DATABASE_URL
python ../scripts/setup_db.py  # Create tables + seed demo data
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
# Or: run_backend.bat (Windows)
```

### Run Frontend
```bash
flutter pub get
flutter run -d windows  # or -d chrome, -d android, etc.
# With custom env:
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000/api/v1
```

### Simulate Telemetry
```bash
# Node.js MQTT simulator (reads backend/.env for broker config)
node test_mqtt.js
# Or Python: python scripts/test_mqtt.py
```

### Database Migrations
Using Alembic. Config in `backend/alembic/`.

---

## 11. Project File Tree (Complete)

```
v_monitor/
├── backend/
│   ├── .env / .env.example
│   ├── requirements.txt
│   ├── alembic/ (migrations)
│   ├── app/
│   │   ├── main.py                  # FastAPI app + MQTT lifespan + CORS
│   │   ├── api/v1/
│   │   │   ├── router.py            # Mount: devices, tracking, geocoding, websocket
│   │   │   ├── devices.py           # GET /, POST /, GET /{id}
│   │   │   ├── tracking.py          # POST /, GET /{id}/history, GET /{id}/history/range, GET /{id}/events
│   │   │   ├── geocoding.py         # GET /reverse
│   │   │   └── websocket.py         # WS /ws
│   │   ├── core/
│   │   │   ├── config.py            # Settings (pydantic-settings)
│   │   │   └── database.py          # Async SQLAlchemy engine + session
│   │   ├── domain/
│   │   │   └── enums.py             # DeviceType, DeviceStatus, UsageStatus, ProcessingStatus
│   │   ├── models/
│   │   │   ├── base.py              # Base, UUIDMixin, TimestampMixin
│   │   │   ├── device.py            # Device table
│   │   │   ├── device_latest_state.py
│   │   │   ├── location_sample.py
│   │   │   ├── telemetry_message.py
│   │   │   ├── device_event.py
│   │   │   ├── usage_session.py
│   │   │   └── audit_log.py
│   │   ├── schemas/
│   │   │   ├── common.py            # BaseSchema, PaginatedResponse
│   │   │   ├── device.py            # DeviceBase/Create/Response/LatestStateResponse
│   │   │   ├── tracking.py          # LocationSample*/LocationHistory*/DeviceEventResponse
│   │   │   └── geocoding.py         # ReverseGeocodeResponse
│   │   └── services/
│   │       ├── device_service.py    # CRUD + format with latest_state join
│   │       ├── tracking_service.py  # Location history + auto event detection
│   │       ├── mqtt_service.py      # MQTT subscriber + telemetry processing
│   │       ├── realtime_service.py  # WebSocket broadcast manager
│   │       └── geocoding_service.py # Nominatim reverse geocode + smart address formatting
│   └── tests/
├── lib/                              # Flutter source (see §4.1 for full tree)
├── test/                             # Flutter unit/widget tests
├── config/                           # JSON env configs (dev/prod/cloudflare)
├── scripts/
│   ├── setup_db.py                  # DB schema creation + demo data seeding
│   ├── test_mqtt.py                 # Python MQTT test client
│   └── test_websocket.py           # Python WebSocket test client
├── test_mqtt.js                     # Node.js MQTT simulator
├── run_backend.bat                  # Windows backend launcher
├── pubspec.yaml                     # Flutter dependencies
├── assets/branding/v_monitor_logo.png
└── analysis_options.yaml
```
