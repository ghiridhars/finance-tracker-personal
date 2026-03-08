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
| 7.2 | Google Drive Sync | ✅ Done | Auto-import bank statements from a Google Drive folder via service account. File type inference from filename conventions. Sync state tracking to skip already-processed files. 4 endpoints: status, list files, sync, reset. Configurable via env vars. |
| 7.3 | Data encryption | ⬜ Not Started | Encrypt account/card numbers at rest. |
| 7.4 | PostgreSQL option | ⬜ Not Started | Multi-device access. |
| 7.5 | Backup/Restore | ⬜ Not Started | One-click DB backup. |

**Files Created (7.1 — Authentication):**
- [backend/app/auth.py](backend/app/auth.py) — JWT auth module: password hashing, token creation/validation, register/login/me/status endpoints, `get_current_user` dependency
- [frontend/lib/services/auth_service.dart](frontend/lib/services/auth_service.dart) — AuthNotifier (Riverpod): login, register, logout, token persistence, auto-validate on startup
- [frontend/lib/screens/login_screen.dart](frontend/lib/screens/login_screen.dart) — Login/register UI with form validation

**Files Created (7.2 — Google Drive Sync):**
- [backend/app/services/gdrive_sync_service.py](backend/app/services/gdrive_sync_service.py) — Google Drive API client, file download, parser dispatch, sync state management
- [backend/app/routers/gdrive.py](backend/app/routers/gdrive.py) — 4 endpoints: status, files, sync, reset

**Files Modified:**
- [backend/app/main.py](backend/app/main.py) — Auth dependency injected into all protected routers; auth_router and gdrive_router registered
- [backend/app/config.py](backend/app/config.py) — Added JWT (secret, algorithm, expiry) and Google Drive (enabled, credentials, folder_id, poll_interval) settings
- [backend/requirements.txt](backend/requirements.txt) — Added python-jose, passlib, google-api-python-client, google-auth
- [frontend/lib/main.dart](frontend/lib/main.dart) — Auth state check wrapping the app; shows LoginScreen when unauthenticated
- [frontend/lib/services/api_service.dart](frontend/lib/services/api_service.dart) — Added static auth token management; Authorization header injected into all requests
- [backend/app/routers/__init__.py](backend/app/routers/__init__.py) — Export gdrive_router

**New API Endpoints (8 new):**

*Authentication (4):*
- `POST /api/auth/register` — Register single user (one-time only)
- `POST /api/auth/login` — OAuth2 password flow, returns JWT
- `GET /api/auth/me` — Get current authenticated user
- `GET /api/auth/status` — Check if any user is registered (public)

*Google Drive Sync (4):*
- `GET /api/v2/gdrive/status` — Sync config and state
- `GET /api/v2/gdrive/files` — List files in Drive folder
- `POST /api/v2/gdrive/sync` — Download + parse new files
- `POST /api/v2/gdrive/reset` — Reset sync state for re-processing
