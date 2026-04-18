# Schema Overhaul: Bank Accounts, Statement Audit & BOB Parsing

Introduce a first-class `bank_accounts` table so accounts are no longer ad-hoc
strings scattered across statements and transactions. Add a `statement_audit`
table to track every parse attempt (success and failure). Fix BOB savings
parsing. Refine the DB Manager to surface the new tables and relationships.

---

## Current problems

1. **No account entity.** Account info lives as raw strings in three places:
   `savings_account_statements.account_number`, `credit_card_statements.card_number`,
   and `unified_transactions.bank + account_identifier`. There's no canonical
   source for "which accounts exist" — they're discovered dynamically.

2. **No parse audit trail.** When a PDF fails or partially parses, there's no
   record. Diagnosing import problems requires re-running the pipeline and
   reading logs.

3. **BOB savings PDFs parse incorrectly.** pdfplumber fragments each BOB PDF
   into dozens of 1-row tables, so Strategy 1 finds only 1-3 out of ~40
   transactions per statement.

4. **MCC codes table not visible.** `mcc_categories` exists in the DB but
   isn't exported from `models/__init__.py` and isn't listed in the DB Manager
   allowlist.

---

## Phase 1 — `bank_accounts` model & auto-creation

### 1.1 New model: `BankAccount`

**File:** `backend/app/models/bank_account.py` (new)

```
Table: bank_accounts
─────────────────────────────────────────────────────
id              Integer     PK, autoincrement
name            String(100) NOT NULL  — user label ("HDFC Savings", "BOB CC")
bank_name       String(30)  NOT NULL  — matches BankType enum value ("HDFC", "BOB")
account_type    Enum        NOT NULL  — StatementType (SAVINGS, CREDIT_CARD)
account_number  String(30)  nullable  — full or masked account/card number
holder_name     String(255) nullable
ifsc_code       String(11)  nullable  — savings only
is_active       Boolean     default True
created_at      DateTime    default utcnow
─────────────────────────────────────────────────────
Unique: (bank_name, account_type, account_number)
```

**Why `bank_name` is a string, not FK:** Banks are a fixed enum, not
user-managed entities. Storing the string keeps things simple and matches
`BankType.value` directly.

### 1.2 FK from statements → bank_accounts

Add a nullable `bank_account_id` FK column to both:
- `savings_account_statements`
- `credit_card_statements`

This replaces the current `account_holder_name` / `card_holder_name` as the
canonical account link. The old columns remain for backward compatibility but
become secondary (populated from the bank_account record).

### 1.3 FK from unified_transactions → bank_accounts

Add a nullable `bank_account_id` FK column to `unified_transactions`. This
replaces `bank` + `account_identifier` as the canonical source. Those columns
remain for backward compatibility and can be derived from the FK.

### 1.4 Auto-creation during import

**File:** `backend/app/services/account_resolution_service.py` (new)

```python
class AccountResolutionService:
    @staticmethod
    def resolve_or_create(
        db, bank_name: str, account_type: StatementType,
        account_number: str | None, holder_name: str | None = None,
    ) -> BankAccount:
        """Find existing account or create one on first import."""
```

Called from `_save_statement()` in the upload router and from local sync's
`scan_and_import()`. Lookup key: `(bank_name, account_type, account_number)`.

### 1.5 Accounts router changes

**File:** `backend/app/routers/accounts.py`

- `GET /api/v2/accounts` → read from `bank_accounts` table directly instead
  of aggregating from statements
- `PATCH /api/v2/accounts/{id}` → update `name`, `holder_name`, `is_active`
- `GET /api/v2/accounts/{id}/statements` → list statements for an account
- Keep existing rename endpoint for backward compat, delegate to new service

### Risks / decisions

| Risk | Mitigation |
|------|------------|
| Account number may be null for some PDFs (parser didn't extract it) | Allow nullable `account_number`; auto-create with `bank_name + account_type` as minimum key. Use a sentinel like `"UNKNOWN"` if needed for uniqueness. |
| Multiple card numbers for the same physical card (masked differently across statements) | The unique constraint `(bank_name, account_type, account_number)` handles this — each variant gets its own record. User can merge via manual edit if desired. |
| `account_type` uses `StatementType` which includes `CSV` and `CURRENT` | Only `SAVINGS` and `CREDIT_CARD` are valid for accounts. Validate on creation. |

---

## Phase 2 — `statement_audit` model & tracking

### 2.1 New model: `StatementAudit`

**File:** `backend/app/models/statement_audit.py` (new)

```
Table: statement_audit
─────────────────────────────────────────────────────
id                  Integer     PK, autoincrement
file_name           String(500) NOT NULL  — original filename
file_hash           String(64)  nullable  — SHA-256 for dedup detection
file_size_bytes     Integer     nullable
bank_account_id     Integer     FK → bank_accounts.id, nullable
bank_name           String(30)  nullable  — denormalized for failed imports where account doesn't exist yet
statement_type      String(20)  NOT NULL  — "SAVINGS" / "CREDIT_CARD"
parser_strategy     String(50)  nullable  — "table", "single_line", "cc_multiline", "cc_simple_multiline", "multiline", "llm"
transaction_count   Integer     default 0
status              String(20)  NOT NULL  — SUCCESS / PARTIAL / FAILED / DUPLICATE / SKIPPED
error_message       Text        nullable
source_statement_id Integer     nullable  — FK to the created savings/CC statement
source              String(20)  NOT NULL  — "upload" / "local_sync" / "gdrive"
imported_at         DateTime    default utcnow
─────────────────────────────────────────────────────
Index: (file_hash)  — for quick duplicate lookups
Index: (status)     — for filtering failures
```

### 2.2 Audit recording points

Audit entries are created at these points in the pipeline:

| Location | When | Status |
|----------|------|--------|
| `parser_service.parse_statement()` | After parsing completes | SUCCESS or FAILED |
| `parser_service.parse_statement()` | When LLM fallback is used | SUCCESS (parser_strategy="llm") |
| `upload.py` `_save_statement()` | After DB save | Updates `source_statement_id` |
| `upload.py` `_save_statement()` | Duplicate detected (IntegrityError) | DUPLICATE |
| `local_sync_service.py` | File skipped (already imported) | SKIPPED |
| `local_sync_service.py` | File import fails | FAILED |

**Decision:** Create the audit entry in `parser_service.parse_statement()` as
the central point. Callers (upload, local sync, gdrive) update it with
`source` and `source_statement_id` after save. This keeps audit creation in
one place.

### 2.3 Logging which strategy succeeded

**File:** `backend/app/parsers/generic_pdf_parser.py`

The `parse()` method already logs which strategy succeeded. To propagate this
to the audit table, `ParseResult` needs an optional `strategy: str` field.
Each strategy sets it before returning:
- `"table"`, `"single_line"`, `"cc_multiline"`, `"cc_simple_multiline"`,
  `"multiline"`

`parser_service.parse_statement()` reads `result.strategy` and passes it to
the audit entry.

### Risks / decisions

| Risk | Mitigation |
|------|------------|
| Audit table grows unbounded | Add a `imported_at` index; provide a cleanup endpoint or auto-prune after N months (future). |
| `bank_account_id` may be null for failed imports | Store `bank_name` as denormalized fallback so we know which bank was attempted. |
| Strategy name may change if we rename methods | Use stable string constants, not method names. |

---

## Phase 3 — BOB savings parsing fix

### 3.1 Problem

pdfplumber fragments BOB savings PDFs into many 1-row tables per page. Each
page starts with a header table containing:
```
['DATE', 'NARRATION', 'CHQ.NO.', 'WITHDRAWAL (DR)', 'DEPOSIT (CR)', 'BALANCE']
```
followed by individual 1-row tables for each transaction. Strategy 1
(`_try_table_strategy`) only parses rows within the same table as the header,
so it picks up 1-3 transactions instead of ~40.

### 3.2 Fix: Merge table fragments in Strategy 1

**File:** `backend/app/parsers/generic_pdf_parser.py`

In `_try_table_strategy()`, before parsing rows:

1. For each page, collect all extracted tables.
2. If a table contains a recognized header row (via `is_table_header()`),
   record the column count.
3. Subsequent tables on the same page with the same column count and no header
   of their own → append their rows to the header table.
4. Repeat across pages — if the next page starts with a header-less table
   matching the column count, merge it too.

This turns the fragmented BOB tables into one logical table per statement.

### 3.3 Balance suffix handling

BOB balances have a `Cr` suffix (`1982.68 Cr`). The existing `parse_amount()`
utility strips currency symbols but not `Cr`/`Dr` suffixes.

**File:** `backend/app/parsers/patterns.py`

Update `parse_amount()` to strip trailing ` Cr` / ` Dr` suffixes and return
the numeric value. The `Cr`/`Dr` indicator is informational only (redundant
with the debit/credit column).

### Risks / decisions

| Risk | Mitigation |
|------|------------|
| Merging may combine unrelated tables on the same page (e.g., summary table + transaction table) | Only merge when column count matches the header table exactly. Summary tables typically have different column counts (2-4 cols vs 6 for transactions). |
| `Cr`/`Dr` suffix removal could affect other parsers | Only strip at end of string after a space: `re.sub(r"\s+(Cr|Dr)\s*$", "", value, flags=re.IGNORECASE)`. This won't match mid-string occurrences. |
| Some BOB PDFs may have different page layouts | Test all 7 BOB files after the fix. 1 currently fails entirely (Feb 2018) — investigate separately. |

---

## Phase 4 — DB Manager & frontend refinements

### 4.1 Expose new tables in admin allowlist

**File:** `backend/app/routers/admin.py`

Add to `ALLOWED_TABLES`:
- `bank_accounts`
- `statement_audit`

Ensure `mcc_categories` is already present (it is — confirmed in the
allowlist).

### 4.2 Export `MccCategory` from models

**File:** `backend/app/models/__init__.py`

Add `MccCategory` to the imports so that `Base.metadata.create_all()` sees it
and the admin router can introspect it properly.

### 4.3 Statement audit log view

**File:** `frontend/lib/screens/database_manager_screen.dart` (or new screen)

Option A: Reuse the existing DB Manager — the `statement_audit` table is
already browsable once added to the allowlist. The search and sort
capabilities handle filtering by status/filename.

Option B: Dedicated audit screen with:
- Filter chips for status (SUCCESS / FAILED / DUPLICATE / SKIPPED)
- Color-coded status badges
- Click-to-expand for error messages
- Date range filter

**Recommendation:** Start with Option A (zero frontend work). Add Option B
later if the raw table view proves insufficient.

### 4.4 Account → statements navigation

**File:** `frontend/lib/screens/database_manager_screen.dart`

When viewing the `bank_accounts` table, add a "View Statements" action button
per row that navigates to the statements table pre-filtered by
`bank_account_id`.

Implementation: The DB Manager already supports `search` — this can be done by
setting a filter on the `bank_account_id` column. Requires a minor extension
to support column-specific filtering in addition to the current full-text
search.

### Risks / decisions

| Risk | Mitigation |
|------|------------|
| DB Manager column filter adds complexity | Start with a simple approach: "View Statements" navigates to the statements table and pre-fills the search box with the account ID. Not ideal but works with zero backend changes. Proper column filters can come later. |
| Dedicated audit screen is more work | Defer to later. The admin table browser covers the immediate need. |

---

## Implementation order

```
Phase 1 — bank_accounts model + auto-creation + accounts router
  ├─ 1.1  Create BankAccount model
  ├─ 1.2  Add bank_account_id FK to statements tables
  ├─ 1.3  Add bank_account_id FK to unified_transactions
  ├─ 1.4  Create AccountResolutionService
  ├─ 1.5  Update upload router + local sync to call resolve_or_create()
  └─ 1.6  Update accounts router to read from bank_accounts

Phase 2 — statement_audit model + tracking
  ├─ 2.1  Create StatementAudit model
  ├─ 2.2  Add strategy field to ParseResult
  ├─ 2.3  Record audit in parser_service.parse_statement()
  └─ 2.4  Update upload + local sync to set source + statement_id on audit

Phase 3 — BOB parsing fix
  ├─ 3.1  Merge table fragments in _try_table_strategy()
  ├─ 3.2  Handle Cr/Dr suffix in parse_amount()
  └─ 3.3  Test all 7 BOB files

Phase 4 — DB Manager refinements
  ├─ 4.1  Add bank_accounts + statement_audit to admin allowlist
  ├─ 4.2  Export MccCategory from models/__init__.py
  ├─ 4.3  Statement audit visible via DB Manager (Option A)
  └─ 4.4  Account → statements navigation link
```

**Estimated file touches:**

| Action | Files |
|--------|-------|
| New files | `models/bank_account.py`, `models/statement_audit.py`, `services/account_resolution_service.py` |
| Modified backend | `models/__init__.py`, `models/savings_account.py`, `models/credit_card.py`, `models/transaction.py`, `parsers/generic_pdf_parser.py`, `parsers/base_parser.py`, `parsers/patterns.py`, `services/parser_service.py`, `routers/upload.py`, `routers/admin.py`, `routers/accounts.py`, `services/local_sync_service.py`, `services/accounts_service.py` |
| Modified frontend | `screens/database_manager_screen.dart` (minimal) |

**Total: ~3 new files, ~14 modified files.**

---

## Out of scope (future)

- Account merging UI (combine duplicate masked card numbers)
- Statement re-parse trigger from audit screen
- Auto-prune audit entries older than N months
- Dedicated audit screen with status filters (Option B)
- Column-specific filtering in DB Manager
- Account-level analytics / spending breakdowns
