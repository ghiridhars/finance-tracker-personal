# Codebase Issues & Improvement Areas

Comprehensive audit of issues, debt, and optimization opportunities across
backend, frontend, infrastructure, and tooling.

---

## Table of Contents

1. [Testing](#1-testing)
2. [Dead & Duplicated Code](#2-dead--duplicated-code)
3. [Performance](#3-performance)
4. [Security](#4-security)
5. [Code Quality](#5-code-quality)
6. [Frontend](#6-frontend)
7. [Dependencies](#7-dependencies)
8. [Infrastructure & CI](#8-infrastructure--ci)

---

## 1. Testing

### Coverage Gap

| Area | Test Files | Status |
|------|-----------|--------|
| Parsers (generic PDF, CSV, LLM) | 3 files | Partial |
| Local sync | 1 file | Partial |
| Routers (18 modules, ~122 endpoints) | **0** | Missing |
| Services (17 modules) | **0** | Missing |
| Auth module | **0** | Missing |
| Database layer | **0** | Missing |
| Schemas / DTOs | **0** | Missing |
| Integration (upload→parse→save→query) | **0** | Missing |
| Frontend widgets | 1 file | Minimal |
| Frontend providers | 0 | Missing |

### Specific Problems

- **CI swallows failures**: `backend/.github/workflows/backend.yml` line 55 uses `|| true` on
  the "verify app starts" step, masking startup errors.
- **No shared fixtures**: No `conftest.py`. Each test file writes its own
  monkeypatches and in-memory DB setup, leading to inconsistent patterns and
  poor test isolation.
- **No coverage tracking**: `pytest-cov` is now in `requirements.txt` but not yet
  integrated into CI. No coverage thresholds or reporting.
- **Parser tests are fragile**: Tests in `test_generic_pdf_parser.py` and
  `test_csv_parser.py` depend on specific PDF/CSV fixtures and monkeypatch
  module-level singletons, making them brittle.

---

## 2. Dead & Duplicated Code

### Dead Code

| File | Lines | Issue |
|------|-------|-------|
| `backend/app/services/savings_service.py` | — | ✅ **Removed** — previously called `UnifiedTransactionService.create_from_savings()` which no longer existed. File has been deleted. |
| `backend/app/services/credit_card_service.py` | — | ✅ **Removed** — previously called `UnifiedTransactionService.create_from_credit_card()` which didn't exist. File has been deleted. |
| `backend/app/schemas/common.py` | — | ✅ **Removed** — was an empty file. |
| `backend/app/routers/transactions.py` | 80 | Legacy v1 compatibility shim that queries DB directly instead of delegating to services. |
| `frontend/.../api/transaction_api.dart:11-48` | 38 | `getSavingsTransactions()` and `getCreditCardTransactions()` call legacy v1 endpoints `/api/transactions/savings` + `/api/transactions/credit-card`. These routes are the dead v1 shim above, not the unified v2 endpoint. |

### Duplicated Code

| Pattern | Files | Impact |
|---------|-------|--------|
| Parse-and-save logic (CSV vs PDF branching, state tracking) | `gdrive_sync_service.py:472-543` + `local_sync_service.py:336-434` | ~70 lines of near-identical CSV/PDF parse branching duplicated (reduced from ~150 by refactoring) |
| `_tx_to_dict` helper | `routers/transactions.py:69` + `routers/export.py:133` | Simple shared serializer would eliminate duplication |
| `review_status` from parser name | ~~`local_sync_service.py`, `gdrive_sync_service.py`, `routers/upload.py`~~ | ✅ **Resolved** — Extracted to shared `utils/file_utils.py:17` `review_status_from_parser()`, used by all three callers |
| Notifier methods (`setDateRange`, `applyPreset`, `loadTransactions`) | `frontend/.../transactions_provider.dart:62-110` vs `:113-161` | Identical code duplicated across 3 notifier classes |
| Statement save with dedup | `credit_card_service.py:50-83` + `savings_service.py:49-83` | Nearly identical save+dedup+create-unified flow |
| `str(e)` in sync result details | `gdrive_sync_service.py:578-582`, `local_sync_service.py` | Exception message exposed verbatim in GDrive sync response; local sync no longer exposes raw `str(e)` |

---

## 3. Performance

### N+1 Query Problems

| Location | Lines | Problem |
|----------|-------|---------|
| `analytics_service.py` `spending_trends` (daily) | 258-278 | Runs one sub-query **per day**. 365 queries for a year instead of a single grouped query. |
| `accounts_service.py` `get_accounts()` | 36-98 | Runs 3 queries per account (statement count, tx count, latest audit). 3N+1 total. |
| `budget_service.py` `get_progress()` | 114-139 | Calls `_get_spent` + `_get_rollover` per budgeted category — 2 queries per category. |
| `UnifiedTransaction` category + tags relationships | `models/transaction.py:80-83` | `lazy="selectin"` generates N+1 selects when serializing list responses on the most-called endpoint. |

### Missing Indexes

All on `unified_transactions` table — filtered in nearly every analytics query:

| Column | Filtered In | Impact |
|--------|-------------|--------|
| `date` | Every analytics query, calendar, date-range filters | O(n) scan |
| `type` (CREDIT/DEBIT) | Every analytics query | O(n) scan |
| `bank` | Account filters, bank breakdown | O(n) scan |
| `account_identifier` | Account-centric transaction view | O(n) scan |

Also missing on `statement_audit.period_start`, `period_end`, `statement_type`.

### Bulk Operations in Memory

| Location | What It Loads | Risk |
|----------|--------------|------|
| `transaction_service.py:283` `recategorize_all()` | `db.query(UnifiedTransaction).all()` | All transactions into memory |
| `upi_service.py:128` `rescan_transactions()` | `db.query(UnifiedTransaction).all()` | All transactions into memory |
| `recurring_service.py:41-51` `detect()` | All debit transactions with merchant names | Years of data |
| `transaction_service.py:55` | `db.query(CategoryKeyword).all()` | Loaded on every statement save, no cache |
| `routers/export.py:51-64` | Up to 10,000 transactions | Acceptable but should warn at scale |

### Other

- `app/parsing/extraction/pdf_text.py` reads entire PDF into memory as text — fine for
  statements but unbounded.

---

## 4. Security

| Issue | Location | Severity |
|-------|----------|----------|
| **Default JWT secret hardcoded** | `config.py:12` — `"CHANGE-ME-set-JWT_SECRET-env-var"` | **High** — token forgery if deployed without env var (runtime warning is issued) |
| ~~**JWT_SECRET not set in docker-compose**~~ | ~~`docker-compose.yml:25-26`~~ | ✅ **Fixed** — Now uses `${JWT_SECRET:-CHANGE-ME-set-JWT_SECRET-env-var}` from host env |
| **`str(exc)` in 400 responses** | `main.py:120` — `value_error_handler` returns `str(exc)` to the client | Medium — file paths and internal error messages from `ValueError` raised anywhere in a service (e.g. "Path does not exist: /app/data/...") are leaked |
| **In-memory rate limiter** | `auth.py:144-160` | Medium — resets on restart, doesn't work across workers |
| **Error details leaked in responses** | `routers/upload.py:201` + `local_sync_service.py:444` + `gdrive_sync_service.py:315` — `str(e)` in response | Medium — may leak internals; upload, local-sync, and gdrive-sync all expose raw exception strings |
| **PDF text dumped to disk in debug mode** | `app/parsing/generic_pdf.py:90` — writes `last_parsed_text.txt` next to the parsed file when `settings.debug=True` | Low — full extracted text of a bank statement written to the data directory; sensitive in any environment where debug is left on |
| **No CSV formula injection protection on upload** | `routers/upload.py:227-337` | Low — export side has `_sanitize_csv_field` but upload doesn't validate |
| **LLM parser has no content size limit** | `llm_parser.py` | Low — unbounded text sent to external API |
| **Credentials file read on every request** | `auth.py:132-139` reads `.credentials.json` on every authenticated call | Low — I/O per request, timing vector |

---

## 5. Code Quality

### Overly Large Files

| File | Lines | Issues |
|------|-------|--------|
| `backend/app/parsers/generic_pdf_parser.py` | — | ✅ **Resolved** — Split into modular package `app/parsing/` with strategy, routing, profiles, and extraction directories. |
| `backend/app/services/analytics_service.py` | 518 | All static methods on one class |
| `backend/app/services/local_sync_service.py` | 584 | Path security, state mgmt, file scanning, import logic, job tracking mixed |
| `backend/app/routers/admin.py` | 392 | Generic CRUD admin panel touching raw DB via SQLAlchemy Core |
| `frontend/.../dashboard_widget.dart` | 727 | ✅ **Partially resolved** — Charts extracted to `widgets/charts/` (Phase 10), but the screen + edit toolbar + tile controls remain in one file; grew from 681→727 lines |
| `frontend/.../transactions_provider.dart` | ~393 | 3 notifier classes in one file with duplicated code |
| `frontend/.../api_service.dart` | 242 | ✅ **Partially resolved** — Decomposed into `services/api/` modules (Phase 10), but the 242-line barrel facade still exists as legacy compatibility layer (was 304) |

### Complex Functions

| Function | Lines | Problems |
|----------|-------|----------|
| `generic_pdf_parser.py::_parse_txn_line` | — | ✅ **Resolved** — Cleaned up and moved to `app/parsing/strategies/single_line_strategy.py`. |
| `generic_pdf_parser.py::_try_multiline_strategy` + `_try_parse_multiline_block` | — | ✅ **Resolved** — Extracted to modular parser functions in `app/parsing/strategies/multiline_strategy.py`. |
| `gdrive_sync_service.py::sync_from_drive` | ~200 lines | Similar to local sync — deeply nested try/except, file download, parse branching, state management, error handling mixed |
| `local_sync_service.py::scan_and_import` | ~200 lines | Deeply nested try/except, mixed concerns |

### Inconsistent Patterns

- **Service layer**: 8 services use `@staticmethod` classes, 2 use instance
  methods, 2 mix both. Makes testing inconsistent.
- **Optional parameters**: `upi_service.py:84` uses sentinel `...` (Ellipsis)
  pattern instead of plain `Optional`, unlike all other services.
- **Lazy imports**: Multiple files use deferred imports inside functions to
  avoid circular dependencies (`transaction_service.py:289`,
  `local_sync_service.py:241-245`, `llm_parser.py:103`, `export.py:154`),
  indicating a need for flatter module structure.
- **Router auth applied via mutation**: `main.py:187` appends `get_current_user`
  to each router's dependency list in a loop. Fragile — any new router added
  to `app.include_router()` outside this loop would be silently unprotected.
  A dedicated `protected_prefix` router or explicit dependency per router
  would be safer.
- **GDrive sync state file not protected by async lock**: `gdrive_sync_service.py:586-588`
  writes state to disk without an async lock. A `_jobs_lock` (line 36) was added to
  protect the in-memory jobs dict, but the state file writes (`state_file.write_text`)
  at lines 588 and 600 still lack protection — concurrent Drive sync requests
  could corrupt the state file.
- **In-memory job tracking (both sync services)**: `local_sync_service.py:33` `_jobs`
  dict and `gdrive_sync_service.py:35` `_gdrive_jobs` dict are both module-level.
  Job status is lost on server restart and not visible across workers.

### Other

- No Alembic migrations — `database.py::migrate_schema()` is a hand-rolled
  auto-migration that can't handle renames, type changes, or rollbacks.
- Hardcoded values: `routers/upload.py:298-300` has a second hardcoded 10MB check (`10 * 1024 * 1024`) in a different branch alongside the config-driven check at line 118.
  10,000-row export cap in `routers/export.py:62`.

---

## 6. Frontend

| Issue | Location | Details |
|-------|----------|---------|
| Login bypasses router | `main.dart:41-46` | Uses `Overlay` + `OverlayEntry` instead of GoRouter route — can cause navigation state bugs |
| Redundant API surface | `services/api_service.dart` | 304-line facade with 50+ static methods re-exporting modular `api/` classes — confusing dual API |
| No offline/caching strategy | All providers | Every screen fetches fresh data on every navigation |
| Duplicated notifier code | `providers/transactions_provider.dart:62-161` | `setDateRange`, `applyPreset`, `loadTransactions` duplicated verbatim across 3 notifiers |
| Overly large widget | `widgets/dashboard_widget.dart` (681 lines) | Mixes layout, edit-mode UI, tile wrapper (208 lines), control widgets, date range chips |
| No widget tests | `test/` | Only 2 test files, neither covers the complex dashboard or calendar |
| `Overlay` for login | `main.dart:41-46` | Bypasses GoRouter state; login state managed outside the router |
| Frontend calls legacy v1 API | `api/transaction_api.dart:11-48` | `getSavingsTransactions` + `getCreditCardTransactions` target `/api/transactions/savings` and `/api/transactions/credit-card` — dead v1 shim, not the unified v2 endpoint |
| No global 401 interceptor | `api/api_client.dart:57-61` | `checkAuth()` throws `UnauthorizedException` on 401 but there is no app-level catch; callers that omit try/catch will surface an unhandled exception rather than a redirect to login |
| `JWT stored in SharedPreferences` | `auth_service.dart` | Token stored via `SharedPreferences` instead of Flutter Secure Storage — accessible to other apps on rooted devices |
| Riverpod async side-effect in `build()` | `auth_service.dart` | `AuthNotifier.build()` calls `_initAuth()` as an unawaited async side-effect — Riverpod anti-pattern; state is in a transient `isLoading: true` limbo until the future resolves |

---

## 7. Dependencies

### Backend (`requirements.txt`)

| Issue | Details |
|-------|---------|
| **Duplicate dep** | `bcrypt==4.0.1` is listed separately and also pulled in by `passlib[bcrypt]==1.7.4` |
| **Unnecessary pin** | `starlette==0.38.6` is a transitive dep of FastAPI — risks version conflicts |
| **Unpinned deps** | `pymupdf`, `pandas`, `openpyxl`, `python-dateutil`, `charset-normalizer`, `google-genai`, `ollama`, `google-api-python-client`, `google-auth` all use `>=` — not reproducible |
| ~~**Missing pytest-cov**~~ | ✅ **Fixed** — `pytest-cov==5.0.0` now in `requirements.txt` |
| ~~**Missing ruff**~~ | ✅ **Fixed** — `ruff==0.8.0` now in `requirements.txt` |

### Over-reliance on `>=`

`pymupdf>=1.24.0`, `pandas>=2.2.0`, `openpyxl>=3.1.0`,
`python-dateutil>=2.9.0`, `charset-normalizer>=3.3.0`,
`google-genai>=1.0.0`, `ollama>=0.4.0`, `google-api-python-client>=2.100.0`,
`google-auth>=2.23.0` — 9 deps use `>=` while the rest are pinned with `==`.

### Frontend (`pubspec.yaml`)

All deps appear current and reasonable. No critical issues.

---

## 8. Infrastructure & CI

### Docker

| Issue | Location | Details |
|-------|----------|---------|
| ~~**JWT_SECRET missing**~~ | ~~`docker-compose.yml:25-26`~~ | ✅ **Fixed** — Now set via `${JWT_SECRET:-...}` env var substitution |
| No `.dockerignore` | backend/, frontend/ | Build context includes venv, `.git`, `__pycache__` — bloated images |
| No `apt-get clean` | `backend/Dockerfile:10-12` | After installing `curl`, no `apt-get clean` — slightly larger image |
| No nginx volume mount | `docker-compose.yml` | Frontend nginx config can't be customized at runtime |
| ~~Deprecated `version:` field~~ | ~~`docker-compose.yml:12`~~ | ✅ **Fixed** — `version:` field has been removed |

### CI/CD

| Issue | Location | Details |
|-------|----------|---------|
| `|| true` swallows errors | `backend.yml:55` | "Verify app starts" step never fails |
| Flutter version mismatch | `frontend.yml:18,42` | Env var is `3.29.1` but clone uses `stable` branch — if cache misses, installed Flutter version may differ from the pinned key |
| No SAST scanning | Both workflows | No `bandit`, `trivy`, or dependency vulnerability scanning |
| `upload-pages-artifact@v3` | `frontend.yml:97` | Potentially outdated version |
| ~~`ruff` not in requirements.txt~~ | ~~`backend.yml:40` + `requirements.txt`~~ | ✅ **Fixed** — `ruff==0.8.0` now in `requirements.txt` |

### Misc

| Issue | Details |
|-------|---------|
| No `Makefile` or `Taskfile` | Common dev commands require remembering exact uvicorn/flutter CLIs |
| No pre-commit hooks | No automated linting/formatting on commit |
| `*.db`, `*.db-shm`, `*.db-wal` in repo | SQLite database files appear to be checked into git |

---

## Quick Wins (Estimated 1-2 hours each)

| # | Task | Impact | Effort |
|---|------|--------|--------|
| 1 | ~~Remove `credit_card_service.py` + `savings_service.py` (dead code)~~ | ✅ Done | — |
| 2 | ~~Add `JWT_SECRET` to `docker-compose.yml`~~ | ✅ Done | — |
| 3 | ~~Add indexes on `unified_transactions.date`, `.type`, `.bank`~~ | ✅ Done | — |
| 4 | ~~Remove `|| true` from CI `backend.yml`~~ | ✅ Done | — |
| 5 | ~~Remove empty `schemas/common.py`~~ | ✅ Done | — |
| 6 | ~~Extract duplicated `review_status` logic into shared helper~~ | ✅ Done (`utils/file_utils.py:17`) | — |
| 7 | Create `.dockerignore` files | Medium | 20min |
| 8 | Pin all `>=` deps to exact versions | Low | 30min |
| 9 | ~~Remove duplicate `bcrypt` and unnecessary `starlette` from `requirements.txt`; add `ruff` and `pytest-cov`~~ | ✅ Done | — |
| 10 | ~~Fix Flutter version pinning in CI `frontend.yml`~~ | ✅ Done (uses `${{ env.FLUTTER_VERSION }}` now) | — |
| 11 | Add async lock around state file writes in `gdrive_sync_service.py` (lines 588, 600) — in-memory jobs lock added but disk writes still unprotected | Medium | 15min |
| 12 | Replace `SharedPreferences` JWT storage with `flutter_secure_storage` | High | 1h |
| 13 | ~~Remove deprecated `version: "3.8"` from `docker-compose.yml`~~ | ✅ Done | — |
| 14 | Migrate `getSavingsTransactions` / `getCreditCardTransactions` in `transaction_api.dart` to use the unified v2 endpoint | Medium | 30min |

---

## Priority Matrix

```
                    High Impact                  Low Impact
Urgent       │  Secure JWT storage (flutter) │  Add gdrive state file lock
             │                              │  Create .dockerignore
─────────────┼───────────────────────────────┼────────────────────
Important    │  Add tests (routers/services) │  Pin all deps
             │  Fix N+1 in analytics         │  Add pre-commit hooks
             │  Fix frontend Overlay login   │  Fix legacy API calls in flutter
             │  Add global 401 interceptor   │
```

---

*Generated from comprehensive codebase audit — all findings verified against
source code. File paths are relative to project root.*
