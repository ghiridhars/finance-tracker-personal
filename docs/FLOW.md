# Finance Tracker — User Flows & API Reference

All identified user flows with their corresponding API endpoints.

---

## 1. Statement Upload Flow

Upload a bank statement (PDF or CSV), parse it, and save transactions.

```
User selects bank + statement type → Picks file → Uploads
  → Backend parses (regex or LLM fallback) → Resolves/creates BankAccount
  → Saves statement audit + transactions → Auto-categorizes → Returns result
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List supported banks | GET | `/api/v2/banks` | Returns bank/type combos + LLM availability |
| Upload PDF | POST | `/api/v2/statements/upload` | Params: `bank`, `type` (SAVINGS/CREDIT_CARD), `save` (bool), `password` (optional). Body: PDF file |
| Upload CSV | POST | `/api/v2/statements/upload-csv` | Params: `bank`, `type`, `save`. Body: CSV/TXT file. Auto-detects columns |

---

## 2. Transaction Browsing Flow

View, search, filter, and manage transactions across all sources.

```
User clicks an Account card → Loads filtered transactions for that account
  → Or opens Calendar → Clicks a day → Sees daily transactions popup
  → Can edit category via tappable chip (all views)
  → Can delete transactions (swipe-to-delete)
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List transactions | GET | `/api/v2/transactions` | Params: `from`, `to`, `category_id`, `bank`, `account_identifier`, `source_type`, `type`, `search`, `min_amount`, `max_amount`, `limit` (1–500), `offset` |
| Count transactions | GET | `/api/v2/transactions/count` | Same filters minus limit/offset. Returns total count |
| Get single transaction | GET | `/api/v2/transactions/{id}` | Full transaction detail |
| Update transaction | PATCH | `/api/v2/transactions/{id}` | Body: `category_id`, `merchant_name`, `notes`, `tag_ids` |
| Delete transaction | DELETE | `/api/v2/transactions/{id}` | Permanently removes from unified table |
| Re-categorize all | POST | `/api/v2/transactions/recategorize` | Re-runs auto-categorization engine on all transactions |

**Legacy endpoints** (in `transactions.py`):

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Savings transactions | GET | `/api/transactions/savings` | Params: `from`, `to`. Defaults: last 30 days |
| Credit card transactions | GET | `/api/transactions/credit-card` | Params: `from`, `to`. Defaults: last 30 days |
| All (savings) | GET | `/api/transactions` | Alias for savings. Backward-compatible |

---

## 3. Dashboard & Analytics Flow

View financial summary, charts, and insights. Dashboard layout is fully customizable.

```
User opens Dashboard → Selects time range (7d/30d/90d/6m/1y/all)
  → Loads summary cards + spending trends + category breakdown
  → Can view income vs expense, month-over-month, top merchants
  → Spending calendar shows per-bank daily heatmap
  → FAB → Edit mode → Reorder tiles, toggle visibility, resize width/height
  → Save → Layout persisted to SharedPreferences
```

**Dashboard Customization (client-side):**

| Feature | Details |
|---------|---------|
| Grid system | 12-column responsive grid. Tiles flow into rows based on `colSpan` |
| Width resize | Snap stops: 4, 6, 8, 12 columns via ◀▶ buttons |
| Height resize | 40px increments via ▲▼ buttons (min 120px, max 800px) |
| Reorder | ↑↓ buttons to move tiles up/down |
| Visibility | Toggle tiles on/off (dimmed in edit mode) |
| Responsive | Compact (<600px): all tiles full-width, width controls hidden. Medium (600–1199px): saved layout. Expanded (≥1200px): full controls |
| Persistence | `SharedPreferences` key `dashboard_layout` stores JSON of tile configs |
| Animations | `AnimatedContainer` (300ms) for size, `AnimatedOpacity` (200ms) for visibility |

**7 Dashboard Tiles:** Summary, Spending Calendar, Spending Trends, Category Breakdown, Income vs Expense, Month-over-Month, Top Merchants

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Summary | GET | `/api/v2/analytics/summary` | Params: `from`, `to`. Returns: income, spending, net, tx count, top category, active banks |
| Category breakdown | GET | `/api/v2/analytics/spending-by-category` | Params: `from`, `to`. Returns: name, color, icon, amount, percentage, tx count per category |
| Spending trends | GET | `/api/v2/analytics/spending-trends` | Params: `from`, `to`, `granularity` (daily/weekly/monthly). Time-series data |
| Income vs Expense | GET | `/api/v2/analytics/income-vs-expense` | Params: `from`, `to`. Monthly grouped bar chart data. Defaults: last 12 months |
| Month-over-month | GET | `/api/v2/analytics/month-over-month` | Params: `month` (date). Current vs previous month per category |
| Top merchants | GET | `/api/v2/analytics/top-merchants` | Params: `from`, `to`, `limit` (1–50, default 15). Ranked by spending |
| Spending by bank | GET | `/api/v2/analytics/spending-by-bank` | Params: `from`, `to`. Bank-level aggregation |

---

## 4. Category Management Flow

Create, edit, and configure auto-categorization rules.

```
User views categories → Creates/edits categories → Adds keywords
  → Keywords drive auto-categorization on future uploads
  → Can re-categorize existing transactions
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List categories | GET | `/api/v2/categories` | Returns all top-level categories with keywords |
| Get category | GET | `/api/v2/categories/{id}` | Single category detail |
| Create category | POST | `/api/v2/categories` | Body: `name`, `icon`, `color`, `parent_id`, `keywords` |
| Update category | PUT | `/api/v2/categories/{id}` | Body: `name`, `icon`, `color`, `parent_id` |
| Delete category | DELETE | `/api/v2/categories/{id}` | Removes category (transactions become uncategorized) |
| Add keywords | POST | `/api/v2/categories/{id}/keywords` | Body: `keywords` (list of strings) |
| Remove keyword | DELETE | `/api/v2/categories/keywords/{keyword_id}` | Delete a single keyword rule |

**Default categories (15):** Food & Dining, Transport, Shopping, Bills & Utilities, Entertainment, Health, Travel, Education, Transfers, Salary, Investment, ATM/Cash, EMI/Loan, Insurance, Other.

---

## 5. Tags Flow

Label transactions with custom tags for flexible grouping.

```
User creates tags → Assigns tags to transactions → Filters by tag
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List tags | GET | `/api/v2/tags` | All tags, ordered by name |
| Create tag | POST | `/api/v2/tags` | Body: `name`, `color` (hex) |
| Delete tag | DELETE | `/api/v2/tags/{id}` | Removes tag and all associations |
| Add tag to transaction | POST | `/api/v2/transactions/{tx_id}/tags/{tag_id}` | Creates association |
| Remove tag from transaction | DELETE | `/api/v2/transactions/{tx_id}/tags/{tag_id}` | Removes association |

---

## 6. Accounts & Statement Management Flow

View linked accounts, browse statement history, and manage uploads.

```
User opens Accounts → Sees all linked accounts/cards with summaries
  → Clicks an account → Views filtered transactions inline (UnifiedTransactionListWidget)
  → Can edit category on any transaction → Back button returns to accounts list
  → Can delete statements (cascades to transactions)
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List accounts | GET | `/api/v2/accounts` | All accounts/cards with statement count, tx count, latest balance |
| Savings statements | GET | `/api/v2/accounts/statements/savings` | Params: `account_number`, `limit` (1–200), `offset` |
| Credit card statements | GET | `/api/v2/accounts/statements/credit-card` | Params: `card_number`, `limit` (1–200), `offset` |
| Delete savings statement | DELETE | `/api/v2/accounts/statements/savings/{id}` | Cascade-deletes raw + unified transactions |
| Delete CC statement | DELETE | `/api/v2/accounts/statements/credit-card/{id}` | Cascade-deletes raw + unified transactions |



---

## 7. Budget Management Flow

Set monthly spending limits per category and track progress.

```
User opens Budget → Selects month → Creates budgets per category
  → Views actual vs budgeted spending → Can copy budgets to next month
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List budgets | GET | `/api/v2/budgets` | Params: `year`, `month` (defaults: current month) |
| Budget progress | GET | `/api/v2/budgets/progress` | Params: `year`, `month`. Budget vs actual per category |
| Budget summary | GET | `/api/v2/budgets/summary` | Params: `year`, `month`. Totals: budgeted, spent, % used, over-budget count |
| Create budget | POST | `/api/v2/budgets` | Body: `category_id`, `year`, `month`, `amount`, `rollover`, `notes` |
| Copy budgets | POST | `/api/v2/budgets/copy` | Params: `from_year`, `from_month`, `to_year`, `to_month` |
| Update budget | PATCH | `/api/v2/budgets/{id}` | Body: `amount`, `rollover`, `notes` |
| Delete budget | DELETE | `/api/v2/budgets/{id}` | — |

---

## 8. Savings Goals Flow

Set savings targets and track contributions.

```
User creates goal (name, target, deadline) → Contributes amounts over time
  → Tracks progress % → Goal auto-completes when target is reached
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List goals | GET | `/api/v2/goals` | Params: `include_completed` (bool, default true) |
| Get goal | GET | `/api/v2/goals/{id}` | Single goal with progress |
| Create goal | POST | `/api/v2/goals` | Body: `name`, `target_amount`, `current_amount`, `deadline`, `icon`, `color`, `notes` |
| Update goal | PATCH | `/api/v2/goals/{id}` | Body: any field |
| Contribute | POST | `/api/v2/goals/{id}/contribute` | Params: `amount` (float, > 0). Auto-marks complete at target |
| Delete goal | DELETE | `/api/v2/goals/{id}` | — |

---

## 9. Bill Reminders Flow

Track recurring bills and due dates.

```
User creates reminder (or auto-detects from CC statements)
  → Views upcoming bills → Marks as paid → Recurring bills auto-advance due date
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List reminders | GET | `/api/v2/reminders` | Params: `include_paid` (bool), `upcoming_days` (int) |
| Create reminder | POST | `/api/v2/reminders` | Body: `name`, `amount`, `category_id`, `is_recurring`, `frequency` (MONTHLY/QUARTERLY/YEARLY), `day_of_month`, `next_due_date`, `notes` |
| Update reminder | PATCH | `/api/v2/reminders/{id}` | Body: any field |
| Mark paid | POST | `/api/v2/reminders/{id}/paid` | Recurring bills auto-advance to next due date |
| Delete reminder | DELETE | `/api/v2/reminders/{id}` | — |
| Auto-detect from CC | POST | `/api/v2/reminders/auto-detect` | Creates reminders from credit card statement due dates |

---

## 10. Recurring Transaction Detection Flow

Detect spending patterns automatically.

```
User triggers detection → Algorithm groups by merchant, analyzes consistency
  → Returns patterns with frequency, avg amount → User can mark as subscription
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List patterns | GET | `/api/v2/recurring` | Params: `active_only` (bool, default true) |
| Run detection | POST | `/api/v2/recurring/detect` | Analyzes: amount CV ≤20%, interval CV ≤30%, min 3 occurrences. Classifies WEEKLY/MONTHLY/QUARTERLY/YEARLY |
| Toggle subscription | PATCH | `/api/v2/recurring/{id}/subscription` | Params: `is_subscription` (bool) |
| Delete pattern | DELETE | `/api/v2/recurring/{id}` | — |

---

## 11. Export & Data Management Flow

Export transactions or clear all data.

```
User clicks export → Downloads CSV/JSON with current filters applied
User clicks clear all → Double confirmation → Wipes all data (keeps categories)
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Export transactions | GET | `/api/v2/export/transactions` | Params: `format` (csv/json), plus same filters as unified transactions. Up to 10,000 rows. Returns file download |
| Clear all data | POST | `/api/v2/data/clear-all` | Deletes all transactions, statements, accounts, budgets, goals, reminders. Preserves categories |

---

## 12. Settings Flow (Client-Side)

User preferences stored locally via SharedPreferences.

```
User opens Settings → Toggles theme (light/dark/system)
  → Changes currency (₹/$/€/£) → Configures backend URL → Tests connection
```

| Setting | Storage | Default |
|---------|---------|---------|
| Theme mode | SharedPreferences | System |
| Currency symbol | SharedPreferences | ₹ |
| Backend URL | SharedPreferences | http://localhost:8080 |

**Health check endpoint** used for connection testing:

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Test connection | GET | `/health` | Returns `{ status: "UP", database: true }` |

---

## 13. Authentication Flow

Single-user JWT authentication. Register once, then login on each session.

```
App starts → Checks /api/auth/status (is registered?)
  → If not registered: show Register form → POST /api/auth/register → JWT token → App
  → If registered: show Login form → POST /api/auth/login → JWT token → App
  → Token stored in SharedPreferences → Auto-validated on next launch via GET /api/auth/me
  → All API calls include Authorization: Bearer <token>
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Check registration | GET | `/api/auth/status` | Returns `{ registered: true/false }`. Public endpoint |
| Register | POST | `/api/auth/register` | Body: `{ username, password }`. Min 8-char password. One-time only. Returns JWT token |
| Login | POST | `/api/auth/login` | OAuth2 password flow (form-encoded). Returns JWT token (24h expiry) |
| Get current user | GET | `/api/auth/me` | Returns `{ username }`. Used to validate saved tokens |

**Security details:**
- Password hashed with bcrypt (passlib)
- JWT signed with HS256 (configurable via `JWT_SECRET` env var)
- Credentials stored in `data/.credentials.json` (not in DB)
- All routes except `/health`, `/api/auth/status`, `/api/auth/register`, `/api/auth/login` require valid JWT

---

## 14. Google Drive OAuth Sync Flow

Import bank statements from a user's personal Google Drive using OAuth2 authentication.

```
User clicks "Connect Google Drive" → Redirected to Google consent screen
  → Grants drive.readonly access → Callback exchanges code for tokens
  → User browses folders → Configures folder bank/type mappings
  → Selects files → Triggers background import → Polls progress
```

### Connection & Authentication

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Check status | GET | `/api/v2/gdrive/status` | Returns: connected (bool), email, secrets_configured |
| Get auth URL | GET | `/api/v2/gdrive/auth-url` | Generates Google OAuth consent URL. Requires `credentials_google.json` on server |
| OAuth callback | GET | `/api/v2/gdrive/callback` | Exchanges auth code for access+refresh tokens. Saves to `.gdrive_user_token.json`. Returns HTML success/error page. **Public endpoint** (no JWT required) |
| Disconnect | POST | `/api/v2/gdrive/disconnect` | Revokes access by deleting stored tokens |

### Folder Browsing & Configuration

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List folders | GET | `/api/v2/gdrive/folders` | Params: `parent_id` (default: root). Lists subfolders with config status |
| List files | GET | `/api/v2/gdrive/files` | Params: `folder_id`. Lists PDF/CSV files with inferred bank/type and processed status |
| Get folder configs | GET | `/api/v2/gdrive/folder-configs` | All saved folder → bank/type mappings |
| Save folder config | POST | `/api/v2/gdrive/folder-configs/{folder_id}` | Body: `folder_name`, `bank`, `type`, `label`. Maps a folder to a bank/statement type |
| Delete folder config | DELETE | `/api/v2/gdrive/folder-configs/{folder_id}` | Removes mapping for a folder |

### Import & Progress

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Import files | POST | `/api/v2/gdrive/import` | Body: `files` (list of {filepath, filename, bank, type}), `force` (bool), `bank_passwords` (dict). Downloads + parses in background |
| Import status | GET | `/api/v2/gdrive/import/{job_id}` | Poll progress: total, processed, skipped, failed, current_file, per-file details |
| Reset sync state | POST | `/api/v2/gdrive/reset` | Body: `file_ids` (optional list). Clears processed markers for re-import |

**Configuration:**
- `GDRIVE_OAUTH_SECRETS_FILE` — Path to `credentials_google.json` (Google OAuth client secrets, "Desktop app" type)
- Token stored at `data/.gdrive_user_token.json` (auto-refreshed when expired)
- Folder configs stored at `data/.gdrive_folder_config.json`

---

## 15. Transfer Management Flow

Detect and manage inter-account transfers and CC bill payments.

```
User triggers auto-detection → Algorithm finds matching DEBIT/CREDIT pairs
  → Pairs linked via transfer_group_id → Shown in Transfers list
  → User can manually link/unlink pairs → Update transfer type
  → Transfers excluded from double-counting in analytics
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Detect transfers | POST | `/api/v2/transfers/detect` | Auto-detect matching DEBIT/CREDIT pairs across accounts |
| Link manually | POST | `/api/v2/transfers/link` | Body: `transaction_id_1`, `transaction_id_2`, `transfer_type` (INTERNAL_TRANSFER/CC_BILL_PAYMENT) |
| List pairs | GET | `/api/v2/transfers/` | All linked transfer pairs with transactions |
| Update type | PATCH | `/api/v2/transfers/{transfer_group_id}` | Params: `transfer_type` |
| Unlink pair | DELETE | `/api/v2/transfers/{transfer_group_id}` | Removes transfer linkage |

---

## 16. UPI ID Management Flow

Map UPI handles to accounts and categories for smarter categorization.

```
User adds UPI handles → Marks own UPIs (linked to accounts)
  → Marks third-party UPIs (linked to categories)
  → Own UPIs auto-flag transactions as transfers
  → Third-party UPIs auto-categorize transactions
  → Rescan applies rules retroactively to existing transactions
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List UPI IDs | GET | `/api/v2/upi-ids` | Params: `is_own` (bool), `account_identifier` (string) |
| Create UPI ID | POST | `/api/v2/upi-ids` | Body: `upi_handle` (must contain @), `label`, `account_type`, `account_identifier`, `category_id`, `is_own` |
| Get UPI ID | GET | `/api/v2/upi-ids/{upi_id}` | Single UPI mapping |
| Update UPI ID | PUT | `/api/v2/upi-ids/{upi_id}` | Body: `label`, `account_type`, `account_identifier`, `category_id`, `is_own` |
| Delete UPI ID | DELETE | `/api/v2/upi-ids/{upi_id}` | Removes mapping |
| Rescan transactions | POST | `/api/v2/upi-ids/rescan` | Re-apply UPI-based rules to all existing transactions |

---

## 17. Local Directory Sync Flow

Scan and import bank statements from a local filesystem directory.

```
User configures a local folder path → Scans for PDF/CSV files
  → Reviews detected files with inferred bank/type → Selects files to import
  → Triggers background scan & parse → Polls progress → Files saved to DB
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| Check status | GET | `/api/v2/local-sync/status` | Returns: configured path, path exists, last scan info |
| Configure path | POST | `/api/v2/local-sync/configure` | Body: `{ path }`. Validates directory exists and is readable |
| List files | GET | `/api/v2/local-sync/files` | Params: `path` (optional, uses configured path). Recursively lists PDF/CSV/Excel files with inferred bank/type and processed status |
| Start scan | POST | `/api/v2/local-sync/scan` | Body: `files` (list of {filepath, bank, type}), `force` (bool), `bank_passwords` (dict). Background processing |
| Scan status | GET | `/api/v2/local-sync/scan/{job_id}` | Poll progress: total, processed, skipped, failed, per-file details |
| Reset state | POST | `/api/v2/local-sync/reset` | Body: `filepaths` (optional list). Clears processed markers for re-processing |

**Configuration (env vars):**
- `LOCAL_SYNC_PATH` — Default local folder path
- `LOCAL_SYNC_MAX_FILES` — Max files to return per scan (default: 500)
- `LOCAL_SYNC_ALLOWED_ROOTS` — Comma-separated allowed root directories for security

---

## 18. Admin / Database Manager Flow

Browse, search, and edit database tables through a generic admin interface.

```
User opens Database Manager → Views list of allowed tables
  → Clicks a table → Views schema and rows with search/sort/pagination
  → Can create, update, or delete individual rows
  → Foreign key columns show dropdown options from related tables
```

| Step | Method | Endpoint | Details |
|------|--------|----------|---------|
| List tables | GET | `/api/v2/admin/tables` | Returns allowed tables with column count and row count |
| Get table schema | GET | `/api/v2/admin/tables/{table_name}/schema` | Column metadata: type, nullable, PK, FK, enum values, max length |
| List rows | GET | `/api/v2/admin/tables/{table_name}/rows` | Params: `limit` (1–500), `offset`, `sort`, `order` (asc/desc), `search`. Paginated with search across string columns |
| Create row | POST | `/api/v2/admin/tables/{table_name}/rows` | Body: field-value dict. Autoincrement PK columns auto-stripped |
| Update row | PUT | `/api/v2/admin/tables/{table_name}/rows/{row_id}` | Body: field-value dict. PK columns excluded |
| Delete row | DELETE | `/api/v2/admin/tables/{table_name}/rows/{row_id}` | Deletes by primary key |
| FK options | GET | `/api/v2/admin/tables/{table_name}/fk-options/{column_name}` | Dropdown values for foreign key columns |

**Allowed tables:** `bank_accounts`, `categories`, `category_keywords`, `mcc_categories`, `tags`, `transaction_tags`, `unified_transactions`, `statement_audit`, `budgets`, `savings_goals`, `bill_reminders`, `recurring_transactions`, `upi_ids`

---

## API Summary

| Domain | Endpoints | Version |
|--------|:---------:|---------|
| Health | 1 | — |
| Authentication | 4 | — |
| Legacy Transactions | 3 | v1 |
| Upload (Unified) | 3+ | v2 |
| Categories | 7+ | v2 |
| Unified Transactions | 8 | v2 |
| Tags | 4 | v2 |
| Analytics | 7 | v2 |
| Accounts | 4 | v2 |
| Budgets | 8 | v2 |
| Savings Goals | 7 | v2 |
| Reminders | 12 | v2 |
| Recurring | 4 | v2 |
| Export/Data | 3 | v2 |
| Google Drive (OAuth) | 12 | v2 |
| Transfers | 5 | v2 |
| UPI IDs | 7 | v2 |
| Local Directory Sync | 6 | v2 |
| Admin / Database | 7+ | v2 |
| **Total** | **~122** | |

> All v2 endpoints are prefixed with `/api/v2/`. Legacy v1 endpoints remain at `/api/` for backward compatibility.
> Auth endpoints are at `/api/auth/`. The `/health` and `/api/auth/status` endpoints are public; all others require a valid JWT Bearer token.
> Google Drive `/callback` endpoint is also public (handles OAuth redirect).
> Interactive API docs available at `/docs` (Swagger UI) and `/redoc` (ReDoc) when the backend is running.
