# Personal Finance Management App — Roadmap

> Single tracking file for all phases. Updated after each phase completion.

---

## Phase 1: Multi-Bank Statement Support (Foundation) — ✅ COMPLETED

**Goal:** Replace hardcoded HDFC-only logic with a bank-agnostic architecture that supports any bank via a generic PDF parser (table + text extraction), CSV import, and optional LLM fallback.

| # | Task | Status | Details |
|---|------|--------|---------|
| 1.1 | BankType + StatementType enums (backend) | ✅ Done | `BankType`: HDFC, ICICI, SBI, AXIS, KOTAK, YES_BANK, BOB, FEDERAL_BANK, OTHER. `StatementType`: SAVINGS, CREDIT_CARD, CURRENT, CSV. |
| 1.2 | Generic PDF parser | ✅ Done | `generic_pdf_parser.py` — bank-agnostic parser using table extraction + text-based fallback. Works for any bank without bank-specific code. |
| 1.3 | Unified upload endpoint | ✅ Done | `POST /api/v2/statements/upload?bank=X&type=Y&save=true` — works for any bank. `GET /api/v2/banks` — discovery endpoint for frontend. |
| 1.4 | Generic LLM parser (any bank) | ✅ Done | `parse_with_llm_generic()` — bank-agnostic prompts for both savings + credit card. Works for ICICI, SBI, Axis, etc. without regex parsers. |
| 1.5 | CSV/Excel import | ✅ Done | `csv_parser.py` — auto-detects columns (Date, Description, Debit, Credit, Balance, Ref). `POST /api/v2/statements/upload-csv`. Supports comma/tab/semicolon/pipe delimiters. |
| 1.6 | Frontend — updated bank dropdown | ✅ Done | 9 banks in dropdown (incl. BOB, Federal Bank) + separate statement type selector. File picker now accepts PDF + CSV. Upload uses v2 unified endpoint. |
| 1.7 | Backward compatibility | ✅ Done | All existing v1 endpoints (`/api/credit-card/`, `/api/statements/`, `/api/parse/`) still work unchanged. `ParserService` legacy methods delegate to unified parser. |

**Files Created:**
- [backend/app/parsers/parser_registry.py](backend/app/parsers/parser_registry.py) — Parser registry (register, lookup, list)
- [backend/app/parsers/csv_parser.py](backend/app/parsers/csv_parser.py) — Generic CSV parser with column auto-detection
- [backend/app/routers/upload.py](backend/app/routers/upload.py) — Unified v2 upload endpoints (PDF + CSV)

**Files Modified:**
- [backend/app/models/enums.py](backend/app/models/enums.py) — Added `BankType`, `StatementType` enums
- [backend/app/models/__init__.py](backend/app/models/__init__.py) — Export new enums
- [backend/app/parsers/__init__.py](backend/app/parsers/__init__.py) — Export registry functions
- [backend/app/parsers/llm_parser.py](backend/app/parsers/llm_parser.py) — Added generic bank-agnostic LLM parser + savings prompt
- [backend/app/services/parser_service.py](backend/app/services/parser_service.py) — Registry-driven dispatch, unified `parse_statement()` method
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register upload_router
- [backend/app/main.py](backend/app/main.py) — Include upload_router
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Added v2 upload + CSV + banks endpoints
- [frontend/lib/providers/statements_provider.dart](frontend/lib/providers/statements_provider.dart) — Added `uploadV2()` method
- [frontend/lib/widgets/statement_upload_widget.dart](frontend/lib/widgets/statement_upload_widget.dart) — 7-bank dropdown, statement type selector, CSV support

---

## Phase 2: Unified Data Model & Categorization — ✅ COMPLETED

**Goal:** Normalize all transactions into a single searchable model with auto-categorization.

| # | Task | Status | Details |
|---|------|--------|---------|
| 2.1 | Unified transaction model | ✅ Done | `UnifiedTransaction` table — denormalized from CC + savings. Fields: date, description, amount (always positive), type (CREDIT/DEBIT), source_type (SAVINGS/CREDIT_CARD), bank, account_identifier, category_id (FK), merchant_name, notes, reference_number. Unique constraint on (source_type, source_transaction_id). Auto-created on statement upload. |
| 2.2 | Alembic migrations | ✅ Done | `alembic init`, env.py configured with app models, migration `084fc04be00e` auto-generated detecting 5 new tables (categories, tags, category_keywords, unified_transactions, transaction_tags), applied with `alembic upgrade head`. |
| 2.3 | Auto-categorization engine | ✅ Done | `CategoryService.seed_defaults()` seeds 15 system categories (Food & Dining, Transport, Shopping, Bills & Utilities, Entertainment, Health, Travel, Education, Transfers, Salary, Investment, ATM/Cash, EMI/Loan, Insurance, Other) with keyword lists. `auto_categorize()` does longest-match keyword lookup on descriptions. Runs automatically on statement upload. |
| 2.4 | Manual category override | ✅ Done | `PATCH /api/v2/transactions/{id}` to change category. Frontend category dialog with colored dots on each transaction tile. `POST /api/v2/transactions/recategorize` for bulk re-run. Categories CRUD: `GET/POST/PUT/DELETE /api/v2/categories`, keyword management endpoints. |
| 2.5 | Merchant normalization | ✅ Done | `normalize_merchant()` strips UPI/NEFT/IMPS/POS prefixes, long reference numbers, dates, special chars. Returns clean Title Case merchant name stored on unified transaction. |
| 2.6 | Tags & notes | ✅ Done | `Tag` model (name, color) + `TransactionTag` junction table. `POST/DELETE /api/v2/transactions/{id}/tags/{tag_id}`. Notes field on UnifiedTransaction, editable via PATCH. Tags CRUD: `GET/POST/DELETE /api/v2/tags`. Frontend Tag model + provider ready. |

**Files Created:**
- [backend/app/models/category.py](backend/app/models/category.py) — Category + CategoryKeyword SQLAlchemy models (hierarchical with parent_id)
- [backend/app/models/tag.py](backend/app/models/tag.py) — Tag + TransactionTag junction table
- [backend/app/models/transaction.py](backend/app/models/transaction.py) — UnifiedTransaction denormalized table
- [backend/app/schemas/category.py](backend/app/schemas/category.py) — Category Pydantic DTOs (CRUD + keyword management)
- [backend/app/schemas/tag.py](backend/app/schemas/tag.py) — Tag Pydantic DTOs
- [backend/app/schemas/transaction.py](backend/app/schemas/transaction.py) — UnifiedTransaction DTOs (query params, update schema)
- [backend/app/services/category_service.py](backend/app/services/category_service.py) — Category CRUD + 15 default categories with keywords
- [backend/app/services/categorization_service.py](backend/app/services/categorization_service.py) — Auto-categorization engine + merchant normalization
- [backend/app/services/transaction_service.py](backend/app/services/transaction_service.py) — Unified transaction CRUD, create from sources, query/filter
- [backend/app/routers/categories.py](backend/app/routers/categories.py) — 7 category endpoints (CRUD + keywords)
- [backend/app/routers/unified_transactions.py](backend/app/routers/unified_transactions.py) — 7 transaction endpoints (query, update, tags, recategorize)
- [backend/app/routers/tags.py](backend/app/routers/tags.py) — 3 tag endpoints (list, create, delete)
- [backend/alembic.ini](backend/alembic.ini) — Alembic configuration
- [backend/alembic/](backend/alembic/) — Alembic migrations directory with env.py + initial migration
- [frontend/lib/models/category_models.dart](frontend/lib/models/category_models.dart) — Category, CategoryKeyword, Tag Dart models
- [frontend/lib/models/unified_transaction_models.dart](frontend/lib/models/unified_transaction_models.dart) — UnifiedTransaction Dart model
- [frontend/lib/providers/categories_provider.dart](frontend/lib/providers/categories_provider.dart) — Categories + Tags Riverpod providers
- [frontend/lib/widgets/unified_transaction_list_widget.dart](frontend/lib/widgets/unified_transaction_list_widget.dart) — Unified transaction list with search, filters, category re-assignment

**Files Modified:**
- [backend/app/models/enums.py](backend/app/models/enums.py) — Added `SourceType` enum (SAVINGS, CREDIT_CARD)
- [backend/app/models/__init__.py](backend/app/models/__init__.py) — Export Phase 2 models
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register 3 new routers
- [backend/app/routers/upload.py](backend/app/routers/upload.py) — Pass bank to save + trigger unified transaction creation
- [backend/app/main.py](backend/app/main.py) — Include new routers, seed categories on startup (34 routes total)
- [backend/app/services/credit_card_service.py](backend/app/services/credit_card_service.py) — Call UnifiedTransactionService on save
- [backend/app/services/savings_service.py](backend/app/services/savings_service.py) — Call UnifiedTransactionService on save
- [backend/requirements.txt](backend/requirements.txt) — Added `alembic==1.13.1`
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — 11 new API methods (categories, tags, unified transactions)
- [frontend/lib/providers/transactions_provider.dart](frontend/lib/providers/transactions_provider.dart) — Added UnifiedTransactionsNotifier with filter state
- [frontend/lib/screens/home_screen.dart](frontend/lib/screens/home_screen.dart) — 4 tabs (Upload, All Transactions, Savings, Credit Card)

---

## Phase 3: Dashboard & Analytics — ✅ COMPLETED

**Goal:** Visual spending insights — charts, trends, category breakdowns.

| # | Task | Status | Details |
|---|------|--------|---------|
| 3.1 | Dashboard screen | ✅ Done | Summary cards: income, spending, net savings, transaction count, avg transaction, top spending category, active banks. Date range selector (7d/30d/90d/6m/1y/all). Pull-to-refresh. |
| 3.2 | Spending trends chart | ✅ Done | Line chart with spending (red) and income (green) lines. Auto-adjusts granularity: daily (7-30d), weekly (90d), monthly (6m+). Touch tooltips. |
| 3.3 | Category breakdown | ✅ Done | Interactive pie chart with touch-to-highlight. Color-coded legend with percentages. Includes uncategorized spending. |
| 3.4 | Income vs Expense bar chart | ✅ Done | Grouped bar chart — monthly income (green) vs expense (red). Touch tooltip per bar. Smart Y-axis labels (₹K, ₹L). |
| 3.5 | Spending by bank | ✅ Done | Bank-level aggregation endpoint (`/api/v2/analytics/spending-by-bank`). Replaced CC utilization (requires credit limit data not yet available). |
| 3.6 | Month-over-month comparison | ✅ Done | Current vs previous month total spending with % change badge (green=down, red=up). Per-category comparison table showing current, previous, and % change. Top 8 categories displayed. |
| 3.7 | Top merchants | ✅ Done | Ranked list of top 10 merchants by spending. Progress bars showing relative spend. Transaction count per merchant. |

**Backend Endpoints Created (7 new, 41 total routes):**
- `GET /api/v2/analytics/summary` — Dashboard summary (income, spending, net, top category, banks)
- `GET /api/v2/analytics/spending-by-category` — Category breakdown with colors/icons/percentages
- `GET /api/v2/analytics/spending-trends?granularity=daily|weekly|monthly` — Time-series data
- `GET /api/v2/analytics/income-vs-expense` — Monthly income vs expense
- `GET /api/v2/analytics/month-over-month` — Current vs previous month by category
- `GET /api/v2/analytics/top-merchants?limit=15` — Top merchants by spending
- `GET /api/v2/analytics/spending-by-bank` — Bank-level spending/income split

**Files Created:**
- [backend/app/services/analytics_service.py](backend/app/services/analytics_service.py) — AnalyticsService with 7 aggregate query methods
- [backend/app/routers/analytics.py](backend/app/routers/analytics.py) — 7 analytics API endpoints
- [frontend/lib/models/analytics_models.dart](frontend/lib/models/analytics_models.dart) — DashboardSummary, CategorySpending, SpendingTrend, IncomeVsExpense, MonthOverMonth, MonthComparison, MerchantSpending
- [frontend/lib/providers/dashboard_provider.dart](frontend/lib/providers/dashboard_provider.dart) — DashboardState, DashboardNotifier, DashboardRange enum with date helpers
- [frontend/lib/widgets/dashboard_widget.dart](frontend/lib/widgets/dashboard_widget.dart) — Full dashboard UI: summary cards, line chart, pie chart, bar chart, MoM comparison, top merchants

**Files Modified:**
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register analytics_router
- [backend/app/main.py](backend/app/main.py) — Include analytics_router (41 routes total)
- [frontend/pubspec.yaml](frontend/pubspec.yaml) — Added `fl_chart: ^0.70.2`
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — 7 new analytics API methods
- [frontend/lib/screens/home_screen.dart](frontend/lib/screens/home_screen.dart) — 5 tabs: Dashboard (new first tab), Upload, All Transactions, Savings, Credit Card

---

## Phase 4: Accounts & Statement Management ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 4.1 | Accounts screen | ✅ Done | Accounts list with holder name, masked identifier, bank badge, balance, statement/transaction counts. Tap to drill into statement history. |
| 4.2 | Statement history | ✅ Done | Two-level navigation: accounts list → statement history with back button. Shows savings date ranges and CC statement dates. |
| 4.3 | Delete/Edit APIs | ✅ Done | DELETE endpoints for savings/CC statements (cascade removes unified transactions). DELETE for individual unified transactions. Swipe-to-delete on both statements and transactions. |
| 4.4 | Pagination | ✅ Done | Backend `?limit=&offset=` on statement listing endpoints. PaginatedResponse model in frontend. |
| 4.5 | Search & filter | ✅ Done | Statement filtering by account_number/card_number. Transaction swipe-to-delete with confirmation dialog. |

**New API Endpoints (6 routes, 47 total):**
- `GET /api/v2/accounts` — List all linked savings accounts and credit cards with summary
- `GET /api/v2/accounts/statements/savings?account_number=&limit=&offset=` — Paginated savings statements
- `GET /api/v2/accounts/statements/credit-card?card_number=&limit=&offset=` — Paginated CC statements
- `DELETE /api/v2/accounts/statements/savings/{id}` — Delete savings statement (cascade)
- `DELETE /api/v2/accounts/statements/credit-card/{id}` — Delete CC statement (cascade)
- `DELETE /api/v2/transactions/{id}` — Delete single unified transaction

**Files Created:**
- [backend/app/services/accounts_service.py](backend/app/services/accounts_service.py) — AccountsService (account discovery), StatementManagementService (list/delete statements, delete transactions)
- [backend/app/routers/accounts.py](backend/app/routers/accounts.py) — 5 account/statement management endpoints
- [frontend/lib/models/account_models.dart](frontend/lib/models/account_models.dart) — Account, SavingsStatementSummary, CreditCardStatementSummary, PaginatedResponse
- [frontend/lib/providers/accounts_provider.dart](frontend/lib/providers/accounts_provider.dart) — AccountsState, AccountsNotifier with load/select/delete
- [frontend/lib/widgets/accounts_widget.dart](frontend/lib/widgets/accounts_widget.dart) — Full accounts UI: summary row, account cards, statement history with swipe-to-delete

**Files Modified:**
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register accounts_router
- [backend/app/main.py](backend/app/main.py) — Include accounts_router (47 routes total)
- [backend/app/routers/unified_transactions.py](backend/app/routers/unified_transactions.py) — Added DELETE /{transaction_id} endpoint
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — 7 new methods: getAccounts, getSavingsStatements, getCreditCardStatements, deleteSavingsStatement, deleteCreditCardStatement, deleteTransaction
- [frontend/lib/widgets/unified_transaction_list_widget.dart](frontend/lib/widgets/unified_transaction_list_widget.dart) — Added swipe-to-delete with confirmation dialog
- [frontend/lib/screens/home_screen.dart](frontend/lib/screens/home_screen.dart) — 6 tabs: Dashboard, Upload, All Transactions, Accounts (new), Savings, Credit Card

---

## Phase 5: Budgeting & Goals — ✅ COMPLETED

**Goal:** Monthly budgets per category with progress tracking, savings goals, bill reminders, and recurring transaction detection.

| # | Task | Status | Details |
|---|------|--------|---------|
| 5.1 | Budget system | ✅ Done | Monthly spending limits per category. Budget vs actual progress tracking with rollover support. Summary endpoint with total budgeted, spent, and over-budget count. Copy budgets from previous month. Color-coded progress bars (green/yellow/red). Add/edit/delete budget dialogs. |
| 5.2 | Recurring transaction detection | ✅ Done | Auto-detects recurring patterns by grouping DEBIT transactions by merchant, analyzing amount consistency (≤20% CV) and interval consistency (≤30% CV). Classifies frequency (WEEKLY/MONTHLY/QUARTERLY/YEARLY). MIN_OCCURRENCES = 3. Subscription toggle for manual marking. |
| 5.3 | Savings goals | ✅ Done | Set savings targets with optional deadline. Track progress with percentage and days remaining. Contribute to goals with auto-completion when target is met. Progress bars with color-coded indicators. |
| 5.4 | Bill reminders | ✅ Done | Manual bill creation with frequency (MONTHLY/QUARTERLY/YEARLY). Auto-detect CC dues from latest credit card statement due dates. Mark-as-paid advances next due date for recurring bills. Overdue indicators with days-until-due tracking. |

**New API Endpoints (23 routes, 70 total):**

*Budgets (7):*
- `GET /api/v2/budgets` — List budgets for a month
- `GET /api/v2/budgets/progress` — Budget vs actual spending per category
- `GET /api/v2/budgets/summary` — Overall budget summary (totals, % used, over-budget count)
- `POST /api/v2/budgets` — Create budget
- `POST /api/v2/budgets/copy` — Copy budgets from one month to another
- `PATCH /api/v2/budgets/{id}` — Update budget
- `DELETE /api/v2/budgets/{id}` — Delete budget

*Savings Goals (6):*
- `GET /api/v2/goals` — List goals (optional: include completed)
- `GET /api/v2/goals/{id}` — Get single goal
- `POST /api/v2/goals` — Create goal
- `PATCH /api/v2/goals/{id}` — Update goal
- `POST /api/v2/goals/{id}/contribute` — Add to savings
- `DELETE /api/v2/goals/{id}` — Delete goal

*Bill Reminders (6):*
- `GET /api/v2/reminders` — List reminders (optional: include paid, upcoming days)
- `POST /api/v2/reminders` — Create reminder
- `PATCH /api/v2/reminders/{id}` — Update reminder
- `POST /api/v2/reminders/{id}/paid` — Mark paid (advances due date if recurring)
- `DELETE /api/v2/reminders/{id}` — Delete reminder
- `POST /api/v2/reminders/auto-detect` — Auto-detect CC dues

*Recurring Transactions (4):*
- `GET /api/v2/recurring` — List detected patterns
- `POST /api/v2/recurring/detect` — Run detection algorithm
- `PATCH /api/v2/recurring/{id}/subscription` — Toggle subscription flag
- `DELETE /api/v2/recurring/{id}` — Delete pattern

**Files Created:**
- [backend/app/models/budget.py](backend/app/models/budget.py) — Budget, SavingsGoal, BillReminder, RecurringTransaction SQLAlchemy models
- [backend/app/schemas/budget.py](backend/app/schemas/budget.py) — Pydantic DTOs for all Phase 5 entities (CRUD + progress schemas)
- [backend/app/services/budget_service.py](backend/app/services/budget_service.py) — BudgetService: CRUD + progress tracking + rollover + summary
- [backend/app/services/recurring_service.py](backend/app/services/recurring_service.py) — RecurringDetectionService: pattern detection with statistical analysis
- [backend/app/services/goals_service.py](backend/app/services/goals_service.py) — SavingsGoalService: CRUD + contribute + auto-complete
- [backend/app/services/bill_reminder_service.py](backend/app/services/bill_reminder_service.py) — BillReminderService: CRUD + mark paid + CC auto-detect
- [backend/app/routers/budgets.py](backend/app/routers/budgets.py) — 7 budget endpoints
- [backend/app/routers/goals.py](backend/app/routers/goals.py) — 6 goals endpoints
- [backend/app/routers/reminders.py](backend/app/routers/reminders.py) — 10 endpoints (6 reminders + 4 recurring)
- [frontend/lib/models/budget_models.dart](frontend/lib/models/budget_models.dart) — Budget, BudgetProgress, BudgetSummary, SavingsGoal, BillReminder, RecurringTransaction Dart models
- [frontend/lib/providers/budget_provider.dart](frontend/lib/providers/budget_provider.dart) — BudgetState + BudgetNotifier: manages all Phase 5 data with month navigation
- [frontend/lib/widgets/budget_goals_widget.dart](frontend/lib/widgets/budget_goals_widget.dart) — Full Budget & Goals UI with 4 sections: budget overview, savings goals, bill reminders, recurring transactions

**Files Modified:**
- [backend/app/models/__init__.py](backend/app/models/__init__.py) — Export 4 new models (17 total)
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register budgets_router, goals_router, reminders_router
- [backend/app/main.py](backend/app/main.py) — Include 3 new routers (70 routes total)
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — 20+ new API methods for budgets, goals, reminders, recurring
- [frontend/lib/screens/home_screen.dart](frontend/lib/screens/home_screen.dart) — 7 tabs: Dashboard, Upload, All Transactions, Accounts, Budget & Goals (new), Savings, Credit Card

---

## Phase 6: UX & Polish ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 6.1 | Responsive layout | ✅ Done | NavigationRail (desktop/tablet) + bottom NavigationBar (mobile). Breakpoints: ≥900px expanded sidebar, 600-899px compact rail, <600px bottom nav. |
| 6.2 | Drag-and-drop upload | ✅ Done | Upload widget redesigned with visual drop zone, animated icon transitions, file size display, and change-file action. |
| 6.3 | CSV/PDF export | ✅ Done | Backend export endpoint (CSV/JSON) + browser download via export button in transaction list. |
| 6.4 | Animations & skeleton loading | ✅ Done | Shimmer skeleton placeholders for dashboard, transaction list, accounts, and budget screens. Page transition animations. |
| 6.5 | go_router navigation | ✅ Done | URL-based routing with deep link support. 8 routes via ShellRoute + NoTransitionPage. |
| 6.6 | Settings screen | ✅ Done | Theme mode selector, currency picker (₹/$/€/£), backend URL config with test connection, clear all data with double confirmation. |

**New Endpoints (3, 73 total):**
- `GET /api/v2/export/transactions` — Export filtered transactions as CSV or JSON file download
- `POST /api/v2/data/clear-all` — Delete all user data (transactions, statements, accounts, budgets, goals)
- Settings/preferences are client-side only (SharedPreferences)

**Files Created:**
- [frontend/lib/router.dart](frontend/lib/router.dart) — GoRouter config with 8 routes, ShellRoute, NavDestination metadata
- [frontend/lib/screens/app_shell.dart](frontend/lib/screens/app_shell.dart) — Responsive shell with LayoutBuilder: desktop sidebar, tablet rail, mobile bottom nav
- [frontend/lib/screens/settings_screen.dart](frontend/lib/screens/settings_screen.dart) — Settings UI: theme, currency, backend URL, clear data, about section
- [frontend/lib/widgets/skeleton_widgets.dart](frontend/lib/widgets/skeleton_widgets.dart) — Reusable shimmer skeletons: SkeletonTransactionList, SkeletonDashboard, SkeletonAccountsList, SkeletonBudgetGoals
- [backend/app/routers/export.py](backend/app/routers/export.py) — Export router with CSV/JSON download + clear-all-data endpoint

**Files Modified:**
- [frontend/pubspec.yaml](frontend/pubspec.yaml) — Added go_router, shimmer dependencies
- [frontend/lib/main.dart](frontend/lib/main.dart) — Switched to MaterialApp.router with GoRouter
- [frontend/lib/theme.dart](frontend/lib/theme.dart) — Added page transitions, NavigationRail/Bar theme config
- [frontend/lib/providers/app_settings_provider.dart](frontend/lib/providers/app_settings_provider.dart) — Added currency setting with SharedPreferences persistence
- [frontend/lib/widgets/statement_upload_widget.dart](frontend/lib/widgets/statement_upload_widget.dart) — Redesigned with drag-and-drop zone UI
- [frontend/lib/widgets/unified_transaction_list_widget.dart](frontend/lib/widgets/unified_transaction_list_widget.dart) — Added CSV export button + skeleton loading
- [frontend/lib/widgets/dashboard_widget.dart](frontend/lib/widgets/dashboard_widget.dart) — Replaced CircularProgressIndicator with SkeletonDashboard
- [frontend/lib/widgets/accounts_widget.dart](frontend/lib/widgets/accounts_widget.dart) — Replaced CircularProgressIndicator with SkeletonAccountsList
- [frontend/lib/widgets/budget_goals_widget.dart](frontend/lib/widgets/budget_goals_widget.dart) — Replaced CircularProgressIndicator with SkeletonBudgetGoals
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Added getExportUrl() and clearAllData() methods
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Registered export_router (15 routers total)
- [backend/app/main.py](backend/app/main.py) — Included export_router (73 routes total)

---

## Phase 7: Security, Integrations & Deployment — 🟡 IN PROGRESS

| # | Task | Status | Details |
|---|------|--------|---------|
| 7.1 | Authentication | ✅ Done | Single-user JWT-based auth. Bcrypt password hashing. Register/login endpoints. Credentials stored in local JSON file. OAuth2 password flow. 24-hour token expiry. All API routes (except health + auth) are protected. Frontend login screen with auto-token persistence via SharedPreferences. |
| 7.2 | Google Drive Sync (OAuth2) | ✅ Done | Import bank statements from a user's personal Google Drive via OAuth2. Folder browsing with configurable bank/type mappings. Background download + parse with job tracking. 12 endpoints: status, auth-url, callback, disconnect, folders, files, import, import/{job_id}, reset, folder-configs CRUD. Auto-refresh of expired access tokens. |
| 7.3 | Data encryption | ⬜ Not Started | Encrypt account/card numbers at rest. |
| 7.4 | PostgreSQL option | ⬜ Not Started | Multi-device access. |
| 7.5 | Backup/Restore | ⬜ Not Started | One-click DB backup. |

**Files Created (7.1 — Authentication):**
- [backend/app/auth.py](backend/app/auth.py) — JWT auth module: password hashing, token creation/validation, register/login/me/status endpoints, `get_current_user` dependency
- [frontend/lib/services/auth_service.dart](frontend/lib/services/auth_service.dart) — AuthNotifier (Riverpod): login, register, logout, token persistence, auto-validate on startup
- [frontend/lib/screens/login_screen.dart](frontend/lib/screens/login_screen.dart) — Login/register UI with form validation

**Files Created (7.2 — Google Drive OAuth Sync):**
- [backend/app/services/gdrive_sync_service.py](backend/app/services/gdrive_sync_service.py) — Google Drive OAuth2 client, token management (auto-refresh), folder browsing, file download, parser dispatch, folder config persistence, background job tracking
- [backend/app/routers/gdrive.py](backend/app/routers/gdrive.py) — 12 endpoints: OAuth (status, auth-url, callback, disconnect), browsing (folders, files), import (import, import/{job_id}), state (reset), folder configs (get, save, delete)
- [frontend/lib/services/api/gdrive_api.dart](frontend/lib/services/api/gdrive_api.dart) — Google Drive API client module
- [frontend/lib/providers/gdrive_import_provider.dart](frontend/lib/providers/gdrive_import_provider.dart) — Google Drive OAuth + import state management

**Files Modified:**
- [backend/app/main.py](backend/app/main.py) — Auth dependency injected into all protected routers; auth_router and gdrive_router registered
- [backend/app/config.py](backend/app/config.py) — Added JWT (secret, algorithm, expiry) and Google Drive (`gdrive_oauth_secrets_file`) settings
- [backend/requirements.txt](backend/requirements.txt) — Added python-jose, passlib, google-api-python-client, google-auth
- [frontend/lib/main.dart](frontend/lib/main.dart) — Auth state check wrapping the app; shows LoginScreen when unauthenticated
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Added static auth token management; Authorization header injected into all requests
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Export gdrive_router

**New API Endpoints (16 new):**

*Authentication (4):*
- `POST /api/auth/register` — Register single user (one-time only)
- `POST /api/auth/login` — OAuth2 password flow, returns JWT
- `GET /api/auth/me` — Get current authenticated user
- `GET /api/auth/status` — Check if any user is registered (public)

*Google Drive OAuth (12):*
- `GET /api/v2/gdrive/status` — Check connection status
- `GET /api/v2/gdrive/auth-url` — Generate OAuth consent URL
- `GET /api/v2/gdrive/callback` — OAuth code exchange (public)
- `POST /api/v2/gdrive/disconnect` — Revoke access
- `GET /api/v2/gdrive/folders` — Browse folders
- `GET /api/v2/gdrive/files` — List files in folder
- `POST /api/v2/gdrive/import` — Trigger background import
- `GET /api/v2/gdrive/import/{job_id}` — Poll import progress
- `POST /api/v2/gdrive/reset` — Reset sync state
- `GET /api/v2/gdrive/folder-configs` — List folder mappings
- `POST /api/v2/gdrive/folder-configs/{folder_id}` — Save mapping
- `DELETE /api/v2/gdrive/folder-configs/{folder_id}` — Delete mapping

---

## Phase 8: Customizable Dashboard & Spending Calendar — ✅ COMPLETED

**Goal:** Make the dashboard fully customizable with a responsive grid layout, per-tile resize/reorder/visibility controls, and add a bank-wise spending calendar heatmap.

| # | Task | Status | Details |
|---|------|--------|---------|
| 8.1 | Spending calendar heatmap | ✅ Done | Bank-wise daily spending calendar using `table_calendar`. Days show color-coded cells via `LinearGradient` proportional to per-bank spending. Bank legend auto-generated from data. Fixed color palette for 9 banks. |
| 8.2 | Configurable grid layout | ✅ Done | 12-column grid system. Each tile has `colSpan` (snap stops: 4, 6, 8, 12) and `height` (40px steps, min 120px, max 800px). Tiles flow into rows based on remaining column space. |
| 8.3 | Tile controls (edit mode) | ✅ Done | FAB enters edit mode. Per-tile controls: reorder (↑↓), visibility toggle (👁), width (◀▶) and height (▲▼) resize buttons. Label badge shows tile name + "Xcol · Ypx" size. Reset to defaults + Save buttons. |
| 8.4 | Responsive breakpoints | ✅ Done | `ScreenTier` enum: compact (<600px), medium (600–1199px), expanded (≥1200px). Compact forces all tiles to 12-col full width and hides width controls. |
| 8.5 | Layout persistence | ✅ Done | Dashboard layout (tile order, visibility, colSpan, height) saved to `SharedPreferences` key `dashboard_layout` as JSON. Restored on app load. |
| 8.6 | Smooth animations | ✅ Done | `AnimatedContainer` (300ms easeInOut) for tile size transitions. `AnimatedOpacity` (200ms) for visibility dimming in edit mode. Button-based controls instead of drag handles for smooth UX. |
| 8.7 | Responsive charts | ✅ Done | Charts (`LineChart`, `PieChart`, `BarChart`) use `Expanded` to fill available tile height. Non-chart tiles (`TopMerchants`, `MonthOverMonth`, `Calendar`) use `SingleChildScrollView`/`ListView` to handle overflow within bounded tile containers. |

**Files Created:**
- [frontend/lib/providers/dashboard_layout_provider.dart](frontend/lib/providers/dashboard_layout_provider.dart) — `DashboardLayoutNotifier` with `DashboardTileId` enum (7 tiles), `TileConfig` model, `ScreenTier` enum + `screenTierFor()` factory, `effectiveColSpan()`, `widenTile()`/`narrowTile()`/`tallerTile()`/`shorterTile()` methods, `toggleEditMode()`, `resetToDefaults()`, `reorder()`, `toggleVisibility()`. SharedPreferences persistence.

**Files Modified:**
- [frontend/lib/widgets/dashboard_widget.dart](frontend/lib/widgets/dashboard_widget.dart) — Complete rewrite. `DashboardScreen` with `LayoutBuilder` for responsive `ScreenTier`, `_buildGridRows()` flowing tiles into rows, `_buildRow()` with flex spacer, `_buildSingleTile()` with `AnimatedContainer`. `_EditableTileWrapper` (button-based controls), `_ControlPill`, `_TinyIconButton`. `_SpendingCalendar` with bank-wise `LinearGradient` cells + bank legend. Charts refactored from `SizedBox(height: 220)` to `Expanded`.
- [frontend/lib/models/analytics_models.dart](frontend/lib/models/analytics_models.dart) — Added `AccountSpending` class and `byAccount` field on `SpendingTrend` for per-bank calendar data
- [backend/app/services/analytics_service.py](backend/app/services/analytics_service.py) — `spending_trends()` adds `by_account` array for daily granularity with per-bank spending breakdown
- [frontend/pubspec.yaml](frontend/pubspec.yaml) — Added `table_calendar` dependency

---

## Phase 9: Accounts & Transactions Refactor — ✅ COMPLETED

**Goal:** Remove standalone Transactions/Savings/Credit Card tabs, integrate transaction viewing into the Accounts section, separate the spending calendar into its own full-page screen, and make transaction categories editable everywhere.

| # | Task | Status | Details |
|---|------|--------|---------|
| 9.1 | Spending Calendar as standalone page | ✅ Done | Extracted spending calendar from the dashboard into its own sidebar item (`CalendarScreen`). Full-page view using `table_calendar`. Click a day to see that day's transactions in a popup dialog. |
| 9.2 | Account-centric transactions | ✅ Done | Clicking an account card now shows its filtered transactions inline using `UnifiedTransactionListWidget`, replacing the old `_StatementHistoryView`. Backend supports `account_identifier` query parameter for filtering. |
| 9.3 | Remove redundant sidebar tabs | ✅ Done | Removed standalone "Transactions", "Savings", and "Credit Card" navigation destinations from the sidebar. The Calendar page was added as a new sidebar item. |
| 9.4 | Editable categories in Calendar | ✅ Done | Calendar popup (`_DailyTransactionsPopup`) converted to `ConsumerStatefulWidget`. Tapping a category chip or "+ Category" button opens a picker dialog. Updates refresh the list immediately. |
| 9.5 | Dead code cleanup | ✅ Done | Removed `_StatementHistoryView`, `_SavingsStatementsList`, `_CreditCardStatementsList`, and `_confirmDelete` from `accounts_widget.dart`. |

**Backend Changes:**
- [backend/app/schemas/transaction.py](backend/app/schemas/transaction.py) — Added `account_identifier` to `TransactionQueryParams`
- [backend/app/services/transaction_service.py](backend/app/services/transaction_service.py) — Filter by `account_identifier` in `query()` and `count()`
- [backend/app/routers/unified_transactions.py](backend/app/routers/unified_transactions.py) — Accept `account_identifier` query parameter

**Frontend Changes:**
- [frontend/lib/screens/calendar_screen.dart](frontend/lib/screens/calendar_screen.dart) — New standalone calendar screen with editable categories in daily popup
- [frontend/lib/router.dart](frontend/lib/router.dart) — Removed Transactions/Savings/Credit Card nav destinations; added Calendar
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Added `accountIdentifier` parameter to `getUnifiedTransactions`
- [frontend/lib/providers/transactions_provider.dart](frontend/lib/providers/transactions_provider.dart) — Added `accountIdentifierFilter` to state and notifier
- [frontend/lib/providers/accounts_provider.dart](frontend/lib/providers/accounts_provider.dart) — Simplified `selectAccount` (no longer fetches statements)
- [frontend/lib/widgets/accounts_widget.dart](frontend/lib/widgets/accounts_widget.dart) — Replaced `_StatementHistoryView` with embedded `UnifiedTransactionListWidget`; removed all statement list dead code

---

## Phase 10: Transfer Detection & UPI ID Management — ✅ COMPLETED

**Goal:** Auto-detect inter-account transfers and CC bill payments to avoid double-counting in analytics. Manage UPI handle-to-account/category mappings for smarter auto-categorization and transfer flagging.

| # | Task | Status | Details |
|---|------|--------|---------|
| 10.1 | Transfer detection | ✅ Done | Auto-detect matching DEBIT/CREDIT pairs across accounts within a time window. Groups linked transactions via `transfer_group_id` (UUID). Supports `INTERNAL_TRANSFER` and `CC_BILL_PAYMENT` types. Manual link/unlink endpoints. |
| 10.2 | Transfer model fields | ✅ Done | Added `is_transfer` (bool), `transfer_group_id` (string, indexed), and `transfer_type` (enum) columns to `UnifiedTransaction`. New `TransferType` enum: `INTERNAL_TRANSFER`, `CC_BILL_PAYMENT`. |
| 10.3 | UPI ID management | ✅ Done | `UpiId` model maps UPI handles to accounts and/or categories. Own UPI IDs (`is_own=True`) auto-flag transactions as transfers. Third-party UPI IDs auto-categorize by handle. CRUD endpoints + rescan to retroactively apply rules. |
| 10.4 | Dashboard widget split | ✅ Done | Extracted 6 chart widgets + helpers from `dashboard_widget.dart` into `widgets/charts/` subdirectory for maintainability. |
| 10.5 | API service decomposition | ✅ Done | Split monolithic `api_service.dart` into modular `services/api/` directory with per-domain API files (accounts, analytics, budget, export, transactions, transfers, upload, UPI). |

**New API Endpoints (11 routes, ~81 total):**

*Transfers (5):*
- `POST /api/v2/transfers/detect` — Auto-detect transfer pairs
- `POST /api/v2/transfers/link` — Manually link two transactions
- `GET /api/v2/transfers/` — List all linked pairs
- `PATCH /api/v2/transfers/{transfer_group_id}` — Update transfer type
- `DELETE /api/v2/transfers/{transfer_group_id}` — Unlink a pair

*UPI IDs (6):*
- `GET /api/v2/upi-ids` — List UPI ID mappings
- `POST /api/v2/upi-ids` — Create mapping
- `GET /api/v2/upi-ids/{upi_id}` — Get single mapping
- `PUT /api/v2/upi-ids/{upi_id}` — Update mapping
- `DELETE /api/v2/upi-ids/{upi_id}` — Delete mapping
- `POST /api/v2/upi-ids/rescan` — Re-scan transactions against UPI rules

**Files Created:**
- [backend/app/routers/transfers.py](backend/app/routers/transfers.py) — 5 transfer management endpoints
- [backend/app/services/transfer_detection_service.py](backend/app/services/transfer_detection_service.py) — Auto-detection algorithm + manual link/unlink
- [backend/app/routers/upi.py](backend/app/routers/upi.py) — 6 UPI ID management endpoints
- [backend/app/services/upi_service.py](backend/app/services/upi_service.py) — UPI CRUD + rescan logic
- [backend/app/models/upi.py](backend/app/models/upi.py) — `UpiId` SQLAlchemy model (`upi_ids` table)
- [backend/app/schemas/upi.py](backend/app/schemas/upi.py) — UPI Pydantic DTOs (create, update, response)
- [backend/app/parsing/patterns.py](backend/app/parsing/patterns.py) — Parser pattern utilities
- [frontend/lib/models/upi_models.dart](frontend/lib/models/upi_models.dart) — UPI Dart models
- [frontend/lib/providers/transfers_provider.dart](frontend/lib/providers/transfers_provider.dart) — Transfer state management
- [frontend/lib/providers/upi_provider.dart](frontend/lib/providers/upi_provider.dart) — UPI state management
- [frontend/lib/widgets/upi_management_widget.dart](frontend/lib/widgets/upi_management_widget.dart) — UPI management UI
- [frontend/lib/widgets/charts/](frontend/lib/widgets/charts/) — Extracted chart widgets (chart_helpers, summary_cards, spending_trends_chart, category_pie_chart, income_expense_chart, month_over_month_card, top_merchants_card)
- [frontend/lib/services/api/](frontend/lib/services/api/) — Modular API layer (api_client, account_api, analytics_api, budget_api, export_api, transaction_api, transfers_api, upload_api, upi_api)
- [frontend/lib/models/converters.dart](frontend/lib/models/converters.dart) — Data model converters
- [frontend/lib/providers/date_range_mixin.dart](frontend/lib/providers/date_range_mixin.dart) — Shared date range mixin for providers

**Files Modified:**
- [backend/app/models/enums.py](backend/app/models/enums.py) — Added `TransferType` enum
- [backend/app/models/transaction.py](backend/app/models/transaction.py) — Added `is_transfer`, `transfer_group_id`, `transfer_type` columns
- [backend/app/models/__init__.py](backend/app/models/__init__.py) — Export `UpiId` model
- [backend/app/schemas/transaction.py](backend/app/schemas/transaction.py) — Added `TransferLinkRequest`, `TransferPairSchema`, `TransferDetectResult` schemas; transfer fields in `UnifiedTransactionSchema`
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register `transfers_router`, `upi_router`
- [backend/app/main.py](backend/app/main.py) — Include `transfers_router`, `upi_router`
- [frontend/lib/widgets/dashboard_widget.dart](frontend/lib/widgets/dashboard_widget.dart) — Imports extracted chart components from `charts/` subdirectory

---

## Phase 11: Admin Panel, Local Sync & Data Model Improvements — ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 11.1 | Local Directory Sync | ✅ Done | Scan and import statements from local filesystem folders. Path validation with security constraints. Background scan with job tracking. 6 endpoints: status, configure, files, scan, scan/{job_id}, reset. |
| 11.2 | Database Admin Panel | ✅ Done | Generic CRUD admin interface for all database tables. Schema introspection, paginated row browsing with search/sort, create/update/delete rows, FK dropdown options. 7+ endpoints. Allowlisted table access. |
| 11.3 | BankAccount Model | ✅ Done | First-class `bank_accounts` table replacing scattered account strings. Auto-created on first statement import. Unique constraint on (bank, type, number). |
| 11.4 | StatementAudit Model | ✅ Done | Unified `statement_audit` table tracking every parse attempt with statement-level metadata. Replaces separate credit_card_statements/savings_account_statements metadata. Tracks file hash, parser strategy, source (upload/local_sync/gdrive). |
| 11.5 | MCC Category Codes | ✅ Done | `mcc_categories` table mapping 4-digit Merchant Category Codes to categories. Seeded on startup. Used as fallback in auto-categorization. |
| 11.6 | ReviewStatus Enum | ✅ Done | Added `ReviewStatus` enum (AUTO_PARSED, LLM_PARSED, NEEDS_REVIEW, REVIEWED) for parse confidence lifecycle tracking. |
| 11.7 | Import Screen | ✅ Done | Unified import hub replacing separate upload widget. Combines file upload, local directory sync, and Google Drive import in a single tabbed interface. |
| 11.8 | Account Resolution Service | ✅ Done | Centralized `AccountResolutionService` for resolve-or-create logic when processing statements. Ensures consistent BankAccount linkage. |
| 11.9 | File Utilities | ✅ Done | Shared `utils/file_utils.py` for file type inference, CSV detection, and review status helpers. Reduces code duplication across sync services. |

**Files Created:**
- [backend/app/routers/admin.py](backend/app/routers/admin.py) — 7+ database admin endpoints with table allowlist
- [backend/app/routers/local_sync.py](backend/app/routers/local_sync.py) — 6 local directory sync endpoints
- [backend/app/schemas/admin.py](backend/app/schemas/admin.py) — Admin DTOs (TableInfo, ColumnInfo, RowsResponse, FKOption)
- [backend/app/services/local_sync_service.py](backend/app/services/local_sync_service.py) — Local directory sync: path validation, file scanning, background import, job tracking
- [backend/app/services/account_resolution_service.py](backend/app/services/account_resolution_service.py) — BankAccount resolve-or-create logic
- [backend/app/services/statement_audit_service.py](backend/app/services/statement_audit_service.py) — Statement audit record creation + transaction persistence
- [backend/app/models/bank_account.py](backend/app/models/bank_account.py) — `BankAccount` model (bank_accounts table)
- [backend/app/models/statement_audit.py](backend/app/models/statement_audit.py) — `StatementAudit` model (statement_audit table)
- [backend/app/utils/file_utils.py](backend/app/utils/file_utils.py) — Shared file utilities
- [frontend/lib/screens/import_screen.dart](frontend/lib/screens/import_screen.dart) — Unified import hub (upload + local sync + GDrive)
- [frontend/lib/screens/database_manager_screen.dart](frontend/lib/screens/database_manager_screen.dart) — Database admin browser/editor
- [frontend/lib/models/admin_models.dart](frontend/lib/models/admin_models.dart) — Admin Dart models
- [frontend/lib/providers/admin_provider.dart](frontend/lib/providers/admin_provider.dart) — Admin state management
- [frontend/lib/providers/local_sync_provider.dart](frontend/lib/providers/local_sync_provider.dart) — Local sync state management
- [frontend/lib/services/api/admin_api.dart](frontend/lib/services/api/admin_api.dart) — Admin API module
- [frontend/lib/services/api/local_sync_api.dart](frontend/lib/services/api/local_sync_api.dart) — Local sync API module

**Files Modified:**
- [backend/app/models/enums.py](backend/app/models/enums.py) — Added `ReviewStatus` enum (6 enums total)
- [backend/app/models/category.py](backend/app/models/category.py) — Added `MccCategory` model
- [backend/app/models/__init__.py](backend/app/models/__init__.py) — Export `BankAccount`, `StatementAudit`, `MccCategory` (15+ tables total)
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Register `admin_router`, `local_sync_router` (18 routers total)
- [backend/app/main.py](backend/app/main.py) — Include admin_router, local_sync_router (~122 endpoints total)
- [backend/app/config.py](backend/app/config.py) — Added local sync settings (`local_sync_path`, `local_sync_max_files`, `local_sync_allowed_roots`); updated GDrive to OAuth (`gdrive_oauth_secrets_file`)
- [backend/app/services/category_service.py](backend/app/services/category_service.py) — Added `seed_mcc_codes()` and `upgrade_keywords()` methods
- [frontend/lib/router.dart](frontend/lib/router.dart) — Changed `/upload` to `/import` with legacy redirect

---

## Phase 12: UI Refactoring & Needs Review Pane — ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 12.1 | Needs Review API | ✅ Done | Added `POST /api/v2/transactions/bulk-update` to efficiently update multiple transactions at once. Enhanced `TransactionUpdateSchema` to support `review_status` modifications. |
| 12.2 | Review Notification | ✅ Done | Added a bell icon badge in the AppShell that pulls `needsReviewCount` dynamically from the backend and prompts the user to resolve doubtful parsed transactions. |
| 12.3 | Review Pane Screen | ✅ Done | Created a dedicated `/review` screen for batch processing doubtful transactions. Provides inline dropdowns for category assignment and text fields for merchant names, with a final "Submit Reviewed" bulk action. |
| 12.4 | Glassmorphism Theme | ✅ Done | Applied Liquid Glass UI techniques to `theme.dart` (translucent surfaces, `BackdropFilter` blurs) to modernize the app's desktop experience. |
| 12.5 | Review Reasons & Approvability | ✅ Done | Added `review_reason` (String) to `UnifiedTransaction` schema extracted from parse validation errors. Redesigned review UI with individual row approvals, fade animations, and inline notes editing. |

**Files Created:**
- [frontend/lib/screens/review_screen.dart](frontend/lib/screens/review_screen.dart) — Dedicated UI for reviewing doubtful transactions.

**Files Modified:**
- [backend/app/schemas/transaction.py](backend/app/schemas/transaction.py) — Added `review_status` to schemas.
- [backend/app/services/transaction_service.py](backend/app/services/transaction_service.py) — Implemented `bulk_update()`.
- [backend/app/routers/unified_transactions.py](backend/app/routers/unified_transactions.py) — Added bulk update endpoint.
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Exported count and bulk update endpoints.
- [frontend/lib/providers/transactions_provider.dart](frontend/lib/providers/transactions_provider.dart) — Added `NeedsReviewCountNotifier`.
- [frontend/lib/screens/app_shell.dart](frontend/lib/screens/app_shell.dart) — Added `_NeedsReviewBadge`.
- [frontend/lib/router.dart](frontend/lib/router.dart) — Registered `/review` route.
- [frontend/lib/theme.dart](frontend/lib/theme.dart) — Implemented glassmorphic styling for cards and navigation bars.

---

## Phase 13: Dashboard Investment Analytics — ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 13.1 | Investment Backend API | ✅ Done | Added `GET /api/v2/analytics/investments` endpoint that parses outbound `DEBIT` transactions tagged with `Investment` or `Insurance` categories. Groups these by `merchant_name` to calculate total capital invested and platform allocations. |
| 13.2 | Dashboard Widget Integration | ✅ Done | Integrated a new glassmorphic `InvestmentPortfolioCard` into the `DashboardScreen`. Features a pie chart for capital allocation and real-time total net-invested calculation. |
| 13.3 | Dynamic Layout Persistence | ✅ Done | Added `DashboardTileId.investments` to the dynamic `dashboardLayoutProvider` so users can move, resize, and hide their investment portfolio widget. |

**Files Created:**
- [frontend/lib/widgets/charts/investment_portfolio_card.dart](frontend/lib/widgets/charts/investment_portfolio_card.dart) — Pie chart widget for investments.

**Files Modified:**
- [backend/app/schemas/analytics.py](backend/app/schemas/analytics.py) — Added `InvestmentAnalyticsResponse`.
- [backend/app/services/analytics_service.py](backend/app/services/analytics_service.py) — Implemented `get_investment_analytics`.
- [backend/app/routers/analytics.py](backend/app/routers/analytics.py) — Added endpoint `/investments`.
- [frontend/lib/models/analytics_models.dart](frontend/lib/models/analytics_models.dart) — Added models for UI.
- [frontend/lib/services/api/analytics_api.dart](frontend/lib/services/api/analytics_api.dart) — Added API wrapper.
- [frontend/lib/providers/dashboard_provider.dart](frontend/lib/providers/dashboard_provider.dart) — Wired investment analytics into concurrent fetch.
- [frontend/lib/providers/dashboard_layout_provider.dart](frontend/lib/providers/dashboard_layout_provider.dart) — Registered new tile type.

---

## Phase 14: Investment Portfolio Expansion & Asset Classes — ✅ COMPLETED

| # | Task | Status | Details |
|---|------|--------|---------|
| 14.1 | Investment Rules Engine (Backend) | ✅ Done | Replaced raw platform grouping with an `InvestmentRule` model (aka `MerchantAlias`). Rules map `keywords` (e.g., "SGB", "Groww") to a specific `platform_name` and an `asset_class` (Mutual Funds, Fixed Deposits, Commodities, etc.). `get_investment_analytics` dynamically applies these rules to outbound transfers. |
| 14.2 | Multidimensional Analytics Output | ✅ Done | Updated `/api/v2/analytics/investments` to return capital divided by Asset Class (`assetClasses`) and by Platform (`platforms`), plus historical 6-month contribution trends (`trends`). |
| 14.3 | Dedicated Investments Screen | ✅ Done | Created a robust `/investments` screen with a `CustomScrollView` and Slivers. Features a hero header for total capital, an interactive Trend Chart, an Asset Class allocation grid, and a Top Platforms list. |
| 14.4 | Discreet Rule Management UI | ✅ Done | Built the `InvestmentRulesSection`—an expandable `ExpansionTile` at the bottom of the Investments Screen. Allows users to create or edit mapping rules directly on the screen without leaving the context of their portfolio. |

**Files Created:**
- `backend/app/models/investment_rule.py` — SQLAlchemy model for rules.
- `backend/app/schemas/investment_rule.py` — Pydantic DTOs.
- `backend/app/routers/investment_rules.py` — CRUD endpoints.
- `frontend/lib/models/investment_rule.dart` — Rule models.
- `frontend/lib/providers/investment_rule_provider.dart` — State management.
- `frontend/lib/widgets/investment_rules_section.dart` — Discreet inline management widget.
- `frontend/lib/screens/investments_screen.dart` — Dedicated `/investments` route.

**Files Modified:**
- `backend/app/services/analytics_service.py` — Enhanced grouping logic using rules.
- `frontend/lib/router.dart` — Added `/investments` navigation.
- `frontend/lib/screens/app_shell.dart` — Added to sidebar navigation.
