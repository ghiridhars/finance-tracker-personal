# Local Directory Sync & Unified Import Screen

Added a "local directory scan & import" feature that lets users point the app at a local folder of bank statements and batch-import them. Then merged the existing file-upload UI and the new directory-import UI into a single unified Import Data screen.

17 files touched → 10 new, 6 modified, 1 deleted. 49 backend tests + 9 frontend tests added.

---

## Phase 1 — Backend Service Layer

### config: Local sync settings
**File:** `backend/app/config.py`  
**Change:** Added three new settings to `Settings`:
- `local_sync_path: str = ""` — persisted configured directory path
- `local_sync_max_files: int = 100` — cap on files per scan to prevent runaway imports
- `local_sync_allowed_roots: str = ""` — comma-separated allowlist for path traversal protection (defaults to user home + data_dir)

### utils: Shared file type inference
**Files:** `backend/app/utils/__init__.py`, `backend/app/utils/file_utils.py`  
**Change:** Extracted file type inference logic into a shared utility module:
- `infer_file_type(filename)` — returns `"pdf"`, `"csv"`, or `None` from extension
- `is_supported_file(filename)` — checks `.pdf` or `.csv` extension
- `is_csv_file(filename)` — checks `.csv` extension

### gdrive: Delegate to shared utils
**File:** `backend/app/services/gdrive_sync_service.py`  
**Change:** Replaced inline `_infer_file_type()` with import from `app.utils.file_utils`. Reduces duplication between GDrive and local sync.

### service: Local sync service
**File:** `backend/app/services/local_sync_service.py`  
**Change:** Created the full local sync service (~470 lines) with:
- **Path configuration** — `configure_path()` validates and persists chosen directory to `.local_sync_config.json`
- **Path traversal protection** — `_validate_path_allowed()` resolves symlinks and checks against `_get_allowed_roots()`. Rejects paths outside allowed roots with `PermissionError`.
- **File discovery** — `list_local_files()` recursively walks the directory, filters to supported types, caps at `max_files`, returns metadata (name, size, type, already-imported status)
- **Scan & import** — `scan_and_import()` processes files sequentially through the existing parser pipeline (`ParserService.parse_statement` → save to DB → create unified transactions → auto-categorize). Tracks per-file status (pending/processing/completed/failed/skipped) in a job dict.
- **Job tracking** — In-memory `_jobs` dict with `get_scan_status()` for progress polling
- **State persistence** — `.local_sync_state.json` tracks previously imported files by SHA-256 hash of absolute path (first 16 chars). Skips already-imported files unless forced.
- **Concurrency guard** — `has_running_scan()` + `_state_lock = asyncio.Lock()` prevents parallel scans and race conditions on state file writes
- **Reset** — `reset_sync_state()` clears the state file for re-importing

---

## Phase 2 — Backend API Layer

### router: Local sync endpoints
**File:** `backend/app/routers/local_sync.py`  
**Change:** Created 6 REST endpoints under `/api/v2/local-sync`:

| Method | Path | Description |
|--------|------|-------------|
| GET | `/status` | Returns current config (path, max_files) and scan state summary |
| POST | `/configure` | Sets the local directory path |
| GET | `/files` | Lists files in configured directory with import status |
| POST | `/scan` | Starts a background scan & import job (returns job_id) |
| GET | `/scan/{job_id}` | Returns scan progress (per-file status, counts) |
| POST | `/reset` | Clears import state for re-processing |

**Key design decisions:**
- `/scan` uses `BackgroundTasks` (FastAPI built-in) — no Celery/RQ dependency needed
- Background task creates its own `SessionLocal()` DB session (request session is closed before BackgroundTasks runs)
- HTTP 409 returned if a scan is already running (concurrent scan guard)
- All path-accepting endpoints validate against allowed roots

### registration: Wire into app
**Files:** `backend/app/routers/__init__.py`, `backend/app/main.py`  
**Change:** Added `local_sync_router` to the router barrel export and registered it in the `protected_routers` list in `main.py`.

---

## Phase 3 — Frontend API & State

### api: Local sync API module
**File:** `frontend/lib/services/api/local_sync_api.dart`  
**Change:** Created API module with methods mirroring all 6 backend endpoints. Uses `ApiClient` for auth and base URL handling.

### facade: Barrel exports
**File:** `frontend/lib/services/api_service.dart`  
**Change:** Added barrel export for `local_sync_api.dart` and 6 facade methods on `ApiService` for backward compatibility with older calling patterns.

### provider: Local sync state management
**File:** `frontend/lib/providers/local_sync_provider.dart`  
**Change:** Created Riverpod provider (~280 lines):
- `LocalSyncFile` — immutable model for file metadata + import status
- `LocalSyncState` — holds config path, file list, scan status, job progress, errors, with `copyWith()`
- `LocalSyncNotifier` — manages async operations (configure, list files, start scan, poll progress, reset)
- Polling — 2-second timer during active scans, auto-stops on completion/failure
- Provider: `localSyncProvider = StateNotifierProvider<LocalSyncNotifier, LocalSyncState>`

---

## Phase 4 — Frontend UI & Routing

### screen: Unified Import Data screen
**File:** `frontend/lib/screens/import_screen.dart`  
**Change:** Created unified Import Data screen (~580 lines) with a `SegmentedButton` toggle between two modes:

- **Upload File** — file picker for individual PDF/CSV uploads (migrated from deleted `statement_upload_widget.dart`). Includes bank/type selection dropdowns, file attachment, upload button with progress indicator, and results display.
- **Directory Import** — path configuration, file listing with status chips, scan controls with progress tracking, and reset capability. Supports desktop folder picker (`file_picker` package) with web text-input fallback.

Both modes share the same card-based layout and theme. Upload mode uses `statementsProvider`, directory mode uses `localSyncProvider`.

### routing: Single import route
**File:** `frontend/lib/router.dart`  
**Change:**
- Replaced separate `/upload` and `/local-sync` routes with single `/import` → `ImportScreen`
- Added `AppRoutes.import_` constant (trailing underscore avoids Dart keyword conflict)
- Legacy `/upload` path redirects to `/import`
- Single "Import" navigation entry with `Icons.publish_outlined`

### cleanup: Deleted old upload widget
**File:** `frontend/lib/widgets/statement_upload_widget.dart`  
**Change:** Deleted — functionality fully migrated into `ImportScreen._buildUploadMode()`.

---

## Phase 5 — Bug Fixes

### fix-1: accounts_widget ref safety in dispose()
**File:** `frontend/lib/widgets/accounts_widget.dart`  
**Problem:** `late final` field initializers lazily called `ref.read()` — if first accessed during `dispose()`, the ref was already deactivated, causing `Bad state: Using "ref" when a widget is about to or has been unmounted`.  
**Fix:** Changed to eagerly initialize notifier references in `initState()` instead of using `late final` with lazy `ref.read()` calls.

### fix-2: Provider mutation during tree finalization
**File:** `frontend/lib/widgets/accounts_widget.dart`  
**Problem:** `clearSelection()` and `resetToDefaults()` called in `dispose()` mutated provider state during widget tree finalization, causing `Tried to modify a provider while the widget tree was building`.  
**Fix:** Wrapped mutations in `Future(() { ... })` to defer execution past tree finalization — the approach recommended by Riverpod's own error message.

---

## Phase 6 — Testing

### Backend tests
**File:** `backend/tests/test_local_sync.py`  
**Change:** 49 unit tests across 5 test classes:

| Class | Tests | Coverage |
|-------|-------|----------|
| `TestLocalSyncConfig` | 7 | Path configuration, persistence, validation |
| `TestLocalSyncFileDiscovery` | 10 | Recursive walk, filtering, max_files cap, empty dirs |
| `TestLocalSyncScanAndImport` | 17 | Full pipeline, skip-already-imported, error handling, job tracking |
| `TestLocalSyncSecurity` | 9 | Path traversal rejection, allowed roots, symlink resolution |
| `TestLocalSyncConcurrency` | 6 | Concurrent scan guard, state lock, running scan detection |

All tests use `monkeypatch` to allow `/tmp` paths and mock parser/DB dependencies.

### Frontend tests
**File:** `frontend/test/local_sync_test.dart`  
**Change:** 9 widget tests:
- Mode toggle (SegmentedButton switches between upload and directory modes)
- Directory mode UI states (unconfigured, configured, file listing, scan progress)
- Error display and reset functionality
- Uses `MockLocalSyncNotifier` and `MockStatementsNotifier` with provider overrides

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Path traversal | `_validate_path_allowed()` resolves symlinks, checks against allowed roots |
| Arbitrary file access | Allowed roots default to user home + data_dir; configurable via `LOCAL_SYNC_ALLOWED_ROOTS` env var |
| Concurrent scan races | `has_running_scan()` guard + HTTP 409 + `asyncio.Lock` on state writes |
| DB session lifecycle | Background task creates own `SessionLocal()` with try/finally (request session already closed) |
| File count DoS | `local_sync_max_files` config caps files per scan (default: 100) |

---

## Files Changed Summary

| Status | File |
|--------|------|
| **Added** | `backend/app/utils/__init__.py` |
| **Added** | `backend/app/utils/file_utils.py` |
| **Added** | `backend/app/services/local_sync_service.py` |
| **Added** | `backend/app/routers/local_sync.py` |
| **Added** | `backend/tests/test_local_sync.py` |
| **Added** | `frontend/lib/services/api/local_sync_api.dart` |
| **Added** | `frontend/lib/providers/local_sync_provider.dart` |
| **Added** | `frontend/lib/screens/import_screen.dart` |
| **Added** | `frontend/test/local_sync_test.dart` |
| Modified | `backend/app/config.py` |
| Modified | `backend/app/main.py` |
| Modified | `backend/app/routers/__init__.py` |
| Modified | `backend/app/services/gdrive_sync_service.py` |
| Modified | `frontend/lib/router.dart` |
| Modified | `frontend/lib/services/api_service.dart` |
| Modified | `frontend/lib/widgets/accounts_widget.dart` |
| **Deleted** | `frontend/lib/widgets/statement_upload_widget.dart` |

---

## Test Results

- **Backend:** 158 tests pass (`python -m pytest tests/ --tb=short -q`)
- **Frontend:** 31 tests pass, 1 pre-existing failure in `model_test.dart` (TransactionType.fromString — unrelated)
- **Frontend analyze:** Clean (71 info-level diagnostics only)
