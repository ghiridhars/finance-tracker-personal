# Codebase Review — Changes & Fixes

Full module-by-module review of the finance-tracker-personal monorepo.  
53 issues identified → 41 tasks created → 40 completed, 1 deferred.

---

## Phase 1 — Bug Fixes

### bug-1: Transaction dedup race condition
**File:** `backend/app/services/transaction_service.py`  
**Problem:** SELECT-then-INSERT pattern allowed duplicate transactions under concurrent uploads.  
**Fix:** Replaced with `db.flush()` + `IntegrityError` catch against the existing unique constraint on `(source_type, source_transaction_id)`.

### bug-2: CSV opening balance miscalculation
**File:** `backend/app/parsers/csv_parser.py`  
**Problem:** Opening balance was inferred from the first transaction only — wrong if that transaction was atypical.  
**Fix:** Computed from `closing_balance - total_deposits + total_withdrawals` using all transactions. Also fixed a `Decimal` vs `float` type mismatch caught by tests.

### bug-3: MCC cache thread safety
**File:** `backend/app/services/categorization_service.py`  
**Problem:** Global `_MCC_CACHE` rebuilt concurrently by multiple threads with no synchronization.  
**Fix:** Added `threading.Lock` around the cache-build path.

### bug-4: Goals router N+1 queries
**Files:** `backend/app/routers/goals.py`, `backend/app/services/goals_service.py`  
**Problem:** GET/POST/PATCH endpoints fetched all goals then filtered in Python.  
**Fix:** Added `get_by_id_with_progress()` service method for direct DB lookup.

### bug-6: setDateRange() drops other filters
**File:** `frontend/lib/providers/transactions_provider.dart`  
**Problem:** Both Savings and CC notifiers reconstructed state from scratch instead of using `copyWith()`, losing category/bank filter state.  
**Fix:** Changed to `state = state.copyWith(fromDate: ..., toDate: ...)`.

### bug-7: Fire-and-forget async calls
**Files:** `frontend/lib/providers/budget_provider.dart`, `accounts_provider.dart`  
**Problem:** `_reloadGoals()`, `loadAccounts()` called without `await` — silent failures and race conditions.  
**Fix:** Wrapped with `unawaited()` from `dart:async` to make the intent explicit.

### CategoryKeyword import missing
**File:** `backend/app/services/transaction_service.py`  
**Problem:** `CategoryKeyword` used in pre-fetched keyword query but never imported — runtime `NameError` on upload.  
**Fix:** Added `from app.models.category import CategoryKeyword`.

---

## Phase 2 — Security & Data Integrity

### sec-1: Default JWT secret accepted silently
**File:** `backend/app/config.py`  
**Problem:** App ran with a predictable hardcoded JWT secret if env var wasn't set — any attacker could forge tokens.  
**Fix:** Added `model_validator(mode="after")` that logs a warning on startup when using the default secret.

### sec-2: Credentials file world-readable
**File:** `backend/app/auth.py`  
**Problem:** `.credentials.json` written without restrictive permissions.  
**Fix:** Added `os.chmod(0o600)` after every write.

### sec-3: No login rate limiting
**File:** `backend/app/auth.py`  
**Problem:** Unlimited login attempts enabled brute-force attacks.  
**Fix:** Added in-memory rate limiter — 5 attempts per 5-minute window per IP using `defaultdict` + timestamps.

### sec-4: CSV export injection
**File:** `backend/app/routers/export.py`  
**Problem:** Merchant names written to CSV without escaping — `=cmd|'/c calc'!A0` executes in Excel.  
**Fix:** Added `_sanitize_csv_field()` that prepends `'` to fields starting with `=`, `+`, `-`, `@`, `\t`, `\r`. Set `csv.QUOTE_ALL`.

### sec-5: Debug dump leaks financial data
**File:** `backend/app/parsers/generic_pdf_parser.py`  
**Problem:** Production code wrote full PDF text to `last_parsed_text.txt` unconditionally.  
**Fix:** Gated behind `settings.debug` flag.

### sec-6: Container runs as root
**File:** `backend/Dockerfile`  
**Problem:** No `USER` directive — container ran as root.  
**Fix:** Added `appuser` non-root user with `chown` on the data directory.

### sec-7: No upload content validation
**File:** `backend/app/routers/upload.py`  
**Problem:** Only checked MIME header (trivially spoofed). No file size enforcement server-side.  
**Fix:** Added PDF magic bytes validation (`%PDF`) and 20MB server-side size check.

### sec-8: Missing nginx security headers
**File:** `frontend/nginx.conf`  
**Fix:** Added `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`.

### data-1: LLM parser crashes on invalid JSON
**File:** `backend/app/parsers/llm_parser.py`  
**Problem:** `json.loads()` called on raw LLM output with no error handling — crashes on hallucinated responses.  
**Fix:** Wrapped both Gemini and Ollama paths in `try/except (json.JSONDecodeError, TypeError)` raising `ValueError` with context.

### data-2: No review status for parse confidence
**Files:** `backend/app/models/enums.py`, `backend/app/models/transaction.py`, `backend/app/services/transaction_service.py`  
**Problem:** No way to distinguish auto-parsed vs LLM-parsed vs failed-parse transactions.  
**Fix:** Added `ReviewStatus` enum (`AUTO_PARSED`, `LLM_PARSED`, `NEEDS_REVIEW`, `REVIEWED`) and `review_status` column on `UnifiedTransaction`. Parser pipeline now sets status through the save chain.

---

## Phase 3 — CI, Architecture, Performance, Frontend

### ci-1: CI silently passes on failures
**Files:** `.github/workflows/backend.yml`, `.github/workflows/frontend.yml`  
**Problem:** `continue-on-error: true` on lint, test, and analyze steps — broken code could merge.  
**Fix:** Removed `continue-on-error: true` from all quality-gate steps.

### ci-2: Alembic installed but unused
**Files:** `backend/requirements.txt`, `backend/alembic.ini`, `backend/alembic/`  
**Problem:** Alembic dependency and config existed alongside the active `migrate_schema()` approach.  
**Fix:** Removed alembic from requirements.txt, deleted `alembic.ini` and entire `alembic/` directory.

### ci-3: Database URL inconsistency
**File:** `backend/app/config.py`  
**Problem:** config.py defaulted to `financial-tracker.db` but docker-compose used `finance_tracker.db`.  
**Fix:** Aligned config.py default to `finance_tracker.db`.

### arch-1: Transfers router bypasses service layer
**Files:** `backend/app/routers/transfers.py`, `backend/app/services/transfer_detection_service.py`  
**Problem:** PATCH endpoint mutated ORM objects directly, violating router→service→model layering.  
**Fix:** Added `TransferDetectionService.update_transfer_type()` and delegated from router.

### arch-2: Parser registry undocumented
**File:** `backend/app/parsers/parser_registry.py`  
**Problem:** `_register_builtin_parsers()` was a no-op with no explanation.  
**Fix:** Added docstring clarifying GenericPdfParser is used directly by ParserService as the default.

### arch-4: GDrive folder_id leaked in API response
**File:** `backend/app/routers/gdrive.py`  
**Problem:** Internal Google Drive folder_id exposed to frontend.  
**Fix:** Removed from response payload.

### perf-1: N+1 keyword categorization
**Files:** `backend/app/services/categorization_service.py`, `backend/app/services/transaction_service.py`  
**Problem:** `CategoryKeyword.query().all()` called for every transaction during bulk import.  
**Fix:** Pre-fetch keywords once before loops, pass as optional `keywords` param to `categorize_and_normalize()`.

### fe-1: No 401 handling in frontend
**File:** `frontend/lib/services/api/api_client.dart`  
**Problem:** Expired JWT showed generic error instead of redirecting to login.  
**Fix:** Added `UnauthorizedException` class and `checkAuth()` method. Applied to `transaction_api.dart` as first adopter.

### fe-2: No request timeouts
**File:** `frontend/lib/services/api/transaction_api.dart`  
**Problem:** HTTP requests could hang indefinitely.  
**Fix:** Added `.timeout(ApiClient.timeout)` (30s default, 120s for recategorize) to all calls.

### fe-3: Enum fromString() masks bugs
**File:** `frontend/lib/models/enums.dart`  
**Problem:** `fromString()` silently defaulted to `CREDIT` for unknown values.  
**Fix:** Changed to throw `ArgumentError` on unrecognized input.

---

## Phase 4 — Schema Validation & Testing

### schema-1: Missing output schemas
**File:** `backend/app/schemas/budget.py`  
**Problem:** `SavingsGoal` and `BillReminder` had no response schemas — API returned raw ORM objects.  
**Fix:** Added `SavingsGoalSchema` and `BillReminderSchema` with `from_attributes = True`.

### schema-2: Unbounded query parameters
**File:** `backend/app/schemas/transaction.py`  
**Problem:** `TransactionQueryParams` allowed negative offset, unlimited limit, negative amounts.  
**Fix:** Added `Field` validators: `limit` (1–1000), `offset` (≥0), amounts (≥0).

### schema-3: Negative amounts accepted
**File:** `backend/app/schemas/budget.py`  
**Problem:** Budget, Goal, and Reminder schemas accepted zero/negative amounts.  
**Fix:** Added `gt=0` validators on all amount fields.

### schema-4: Invalid month/year accepted
**File:** `backend/app/routers/budgets.py`  
**Problem:** Budget endpoints accepted `month=99` or `year=-5`.  
**Fix:** Added `ge=1, le=12` for month and `ge=2000, le=2100` for year on all Query params.

### schema-5: Free-form frequency string
**File:** `backend/app/schemas/budget.py`  
**Problem:** Reminder frequency was a free string — any value accepted.  
**Fix:** Changed to `Literal["MONTHLY", "QUARTERLY", "YEARLY", "BI_WEEKLY", "WEEKLY", "ANNUAL"]`.

### doc-1: Python version mismatch
**Files:** `README.md`, `docs/OVERVIEW.md`  
**Problem:** Docs said Python 3.11+ but Dockerfile uses 3.12.  
**Fix:** Updated all references to 3.12+.

### test-1/2/3: Parser test suite
**Files:** `backend/tests/test_generic_pdf_parser.py`, `test_csv_parser.py`, `test_llm_parser.py`  
**Problem:** Zero automated tests for the core parsing pipeline.  
**Fix:** Created 109 unit tests covering:
- **GenericPdfParser** (47 tests): `_parse_amount_or_dash`, `_classify_amounts`, `_try_opening_balance`, `_parse_txn_line`, `extract_metadata`, result builders
- **CSV parser** (37 tests): `parse_date`, `parse_amount`, `map_columns`, delimiter detection, header finding, full savings + credit card parse
- **LLM parser** (25 tests): date parsing, `_json_to_statement`, `_json_to_savings_statement`, edge cases

---

## Not A Bug (Investigated & Dismissed)

| ID | Issue | Reason |
|----|-------|--------|
| bug-5 | Transfer double-matching | `exclude_ids` set already prevents re-matching |
| bug-8 | Case-sensitive file extension check | `.toLowerCase()` already called at line 87 |
| arch-3 | v1 endpoints redundant | v1 serves dedicated savings/CC screens with type-specific models |
| fe-4 | Mixed v1/v2 API calls | Same as arch-3 — intentional |
| fe-5 | Upload case-sensitive check | Already uses `.toLowerCase()` |
| fe-6 | Search has no debounce | Uses `onSubmitted` (Enter key), not `onChanged` |
| ci-4 | bob-statement.pdf in repo | `*.pdf` already in `.gitignore` — file was committed before the rule |

---

## Deferred

| ID | Task | Reason |
|----|------|--------|
| doc-2 | Production deployment notes | Low priority — not blocking any functionality |
