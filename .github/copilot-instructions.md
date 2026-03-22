# Copilot Instructions

## Build, test, and lint commands

### Repository root

- Start both services with Docker Compose: `docker-compose up --build`

### Backend (`backend`)

- Create/update the virtualenv and install deps:
  - Windows: `python -m venv .venv && .\.venv\Scripts\Activate.ps1 && pip install -r requirements.txt`
- Run the API locally: `uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload`
- Run backend tests: `python -m pytest tests/ --tb=short -q`
- The backend's parser-focused check lives in `test_credit_card_parser.py` and is most reliable as a smoke script when working on parsing behavior: `python test_credit_card_parser.py --pdf ..\credit-card-statement.pdf --mode regex`
- Lint the backend the same way CI does: `pip install ruff && ruff check . --output-format=github`
- Quick app-start verification used by CI: `python -c "from app.main import app; print('FastAPI app created successfully')"`

### Frontend (`frontend`)

- Install deps: `flutter pub get`
- Run the frontend in Chrome: `flutter run -d chrome --web-port 3000`
- Run the frontend on Windows desktop: `flutter run -d windows`
- Analyze: `flutter analyze --no-fatal-infos`
- Run all frontend tests: `flutter test`
- Run a single frontend test file: `flutter test test\widget_test.dart`
- Run a single named frontend test: `flutter test --plain-name "App renders and shows navigation" test\widget_test.dart`
- Build the web app the same way CI does: `flutter build web --release --base-href "/finance-tracker-personal/"`

## High-level architecture

- This is a two-app repo: a FastAPI backend in `backend\app` and a Flutter frontend in `frontend\lib`.
- The backend follows a layered flow of **router -> service -> model/schema**. `backend\app\main.py` creates the app, configures CORS and exception handlers, creates tables on startup, seeds default categories, and registers public vs protected routers.
- Authentication is single-user JWT auth in `backend\app\auth.py`. Credentials are stored in `backend\data\.credentials.json`, not in the database. Protected routers receive `Depends(get_current_user)` centrally in `main.py` rather than per-endpoint.
- Statement ingestion is the core backend pipeline:
  - upload endpoints in `backend\app\routers\upload.py`
  - parser dispatch in `backend\app\services\parser_service.py` and `backend\app\parsers\parser_registry.py`
  - parsing via generic PDF / CSV parsers, with Gemini or Ollama fallback for unsupported PDFs
  - raw statement persistence in credit-card or savings tables
  - denormalized transaction creation in `backend\app\services\transaction_service.py`
  - auto-categorization and merchant normalization in `backend\app\services\categorization_service.py`
- `unified_transactions` is the main query surface for the app. Legacy savings/credit-card endpoints still exist, but most current features read from the unified transaction API under `/api/v2/transactions`.
- SQLite is the default database, configured in `backend\app\database.py` with WAL mode and foreign keys enabled.
- Google Drive sync is a first-class integration, not a side script. The sync routes call the same parsing/storage pipeline and track state in a JSON file.
- The Flutter app boots from `frontend\lib\main.dart` with `ProviderScope`, `MaterialApp.router`, shared theme configuration, and an auth gate that shows `LoginScreen` until the token is validated.
- Routing lives in `frontend\lib\router.dart` with a `ShellRoute` and shared `NavDestination` metadata. Some routes still exist for deep-linking even when they are no longer primary navigation entries.
- Frontend state is organized as **screen/widget -> Riverpod notifier/provider -> API module**. UI widgets should stay thin; async loading and derived state usually belong in providers.
- `frontend\lib\services\api_service.dart` is a compatibility facade and barrel export. New API work should usually go into `frontend\lib\services\api\*.dart` and only keep the facade aligned if older callers still depend on it.
- Dashboard, transaction filters, auth token, backend URL, theme settings, and dashboard layout persistence are all client-driven and rely heavily on `SharedPreferences`.

## File creation policy

- **Do NOT create throwaway helper scripts** (e.g., `setup_x.py`, `move_files.py`, `organize_temp.py`, `create_x_dir.py`) to work around shell limitations. If a shell operation is needed, ask the user to run it, or use the available tools directly.
- **Do NOT create planning or notes files** (e.g., `PLAN.md`, `TODO.md`, `notes.txt`) in the repository. Keep planning in memory or the session workspace.
- **Do NOT create test files at module root level** (e.g., `backend/test_foo.py`) — tests belong in `backend/tests/`.
- **When uncertain whether a file is needed**, ask the user before creating it. Prefer modifying existing files over creating new ones.

## Key conventions

- Preserve the backend layering. New endpoint behavior should usually be added in a router and delegated into a service class instead of embedding business logic directly in route handlers.
- Backend services are commonly used as static namespaces rather than instantiated classes. Follow the existing `Service.method(db, ...)` style before introducing stateful service objects.
- Return Pydantic schemas from routes, not raw ORM objects. Existing routers commonly call `Schema.model_validate(...)` before returning data.
- Reuse the unified transaction model for cross-account features. If a new feature needs transaction browsing, filtering, categorization, or analytics, prefer wiring it through `UnifiedTransaction` instead of duplicating logic against raw savings or credit-card tables.
- New parser support should go through the parser layer and registry. Do not hardcode bank-specific parsing logic into upload routes.
- Auto-categorization is keyword-driven and merchant normalization is regex-based. If categorization looks wrong, check `categorization_service.py` and category keywords before changing frontend behavior.
- On the frontend, Riverpod state objects consistently use immutable data plus `copyWith()`. Extend existing state objects rather than introducing ad hoc mutable state in widgets.
- Several providers auto-load data from `build()` or immediately after state changes. When adding new provider methods, keep those refresh patterns consistent so uploads, edits, and filters remain reactive.
- API auth is handled centrally. Frontend code should rely on the shared API/auth services for bearer token setup instead of attaching headers ad hoc in widgets.
- Keep navigation metadata centralized in `router.dart`. When adding a new major screen, update the route constants and shared destination metadata together.

## Existing docs worth reusing

- `README.md` is the best quick-start reference for local setup and the supported feature set.
- `docs\ARCHITECTURE.md` contains the clearest big-picture diagrams for the upload pipeline, auth flow, frontend hierarchy, and Google Drive sync.
- `docs\FLOW.md` is the best source for endpoint usage and cross-feature flows.
- `docs\OVERVIEW.md` is the most complete reference for backend/frontend layering, schema shape, and deployment assumptions.
