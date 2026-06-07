# Finance Tracker — Technical Overview

Complete technical specification: architecture, database schema, API details, and future enhancements.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Tech Stack](#tech-stack)
3. [Backend](#backend)
4. [Frontend](#frontend)
5. [Database Schema](#database-schema)
6. [API Specification](#api-specification)
7. [Parsers](#parsers)
8. [Auto-Categorization](#auto-categorization)
9. [Deployment](#deployment)
10. [Migration History](#migration-history)
11. [Future Enhancements](#future-enhancements)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Frontend                             │
│        Flutter 3.x (Web / Windows Desktop)              │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐            │
│  │ GoRouter  │  │ Riverpod │  │  Widgets   │            │
│  │ (5 nav)   │  │ (State)  │  │ (Material 3)│           │
│  └──────────┘  └──────────┘  └────────────┘            │
│               ↕ HTTP (REST JSON)                        │
├─────────────────────────────────────────────────────────┤
│                     Backend                              │
│           Python 3.12+ / FastAPI 0.115                  │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐            │
│  │ Routers  │  │ Services │  │  Parsers   │            │
│  │ (18 mods)│  │ (logic)  │  │ (PDF/CSV)  │            │
│  └──────────┘  └──────────┘  └────────────┘            │
│               ↕ SQLAlchemy ORM                          │
├─────────────────────────────────────────────────────────┤
│                    Database                              │
│          SQLite (WAL mode, foreign keys)                │
│            15+ tables, 6 enums                          │
└─────────────────────────────────────────────────────────┘
```

**Key patterns:**
- Backend follows **Router → Service → Model** layering
- Frontend follows **Screen → Widget → Provider → API Service** layering
- All API responses use Pydantic DTOs (no ORM objects leaked)
- State management via Riverpod `Notifier` pattern (Riverpod 3.x)
- Navigation via GoRouter `ShellRoute` with responsive app shell

---

## Tech Stack

### Backend

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Python | 3.12+ |
| Framework | FastAPI | 0.115.0 |
| ASGI Server | Uvicorn | 0.30.6 |
| ORM | SQLAlchemy | 2.0.35 |
| Migrations | (hand-rolled `migrate_schema()`) | — |
| Validation | Pydantic | 2.9.2 |
| Settings | pydantic-settings | 2.5.2 |
| PDF Parsing | pdfplumber | 0.11.4 |
| LLM (Gemini) | google-genai | ≥1.0.0 |
| LLM (Ollama) | ollama | ≥0.4.0 |
| Testing | pytest + httpx | 8.3.3 / 0.27.2 |

### Frontend

| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter | 3.x (SDK ≥3.9.2) |
| Language | Dart | 3.x |
| State Management | flutter_riverpod | 3.2.1 |
| Routing | go_router | 15.1.3 |
| Charts | fl_chart | 0.70.2 |
| File Picker | file_picker | 10.3.10 |
| HTTP | http | 1.6.0 |
| Storage | shared_preferences | 2.5.4 |
| Loading Effects | shimmer | 3.0.0 |
| URL Launch | url_launcher | 6.3.1 |
| Formatting | intl | 0.20.2 |

---

## Backend

### Directory Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app, CORS, lifespan, routers
│   ├── config.py               # Settings from env/.env
│   ├── database.py             # SQLAlchemy engine, session, Base
│   ├── auth.py                 # JWT authentication (register/login, get_current_user dependency)
│   ├── models/
│   │   ├── enums.py            # TransactionType, BankType, StatementType, SourceType, TransferType, ReviewStatus
│   │   ├── credit_card.py      # CreditCardStatement, CreditCardTransaction
│   │   ├── savings_account.py  # SavingsAccountStatement, SavingsAccountTransaction
│   │   ├── transaction.py      # UnifiedTransaction (denormalized)
│   │   ├── category.py         # Category, CategoryKeyword, MccCategory
│   │   ├── tag.py              # Tag, TransactionTag
│   │   ├── budget.py           # Budget, SavingsGoal, BillReminder, RecurringTransaction
│   │   ├── upi.py              # UpiId (UPI handle mappings)
│   │   ├── bank_account.py     # BankAccount (first-class account entity)
│   │   └── statement_audit.py  # StatementAudit (parse tracking + statement metadata)
│   ├── schemas/
│   │   ├── credit_card.py      # Credit card DTOs
│   │   ├── savings_account.py  # Savings DTOs
│   │   ├── category.py         # Category CRUD DTOs
│   │   ├── tag.py              # Tag DTOs
│   │   ├── transaction.py      # UnifiedTransaction query/update DTOs + transfer schemas
│   │   ├── budget.py           # Budget, Goal, Reminder, Recurring DTOs
│   │   ├── upi.py              # UPI ID DTOs (create, update, response)
│   │   └── admin.py            # Admin / Database Manager DTOs
│   ├── parsing/                 # Refactored modular parsing engine
│   │   ├── generic_pdf.py       # Generic PDF parsing orchestration
│   │   ├── engine.py            # Parsing engine abstractions
│   │   ├── routing.py           # Strategy route resolution & profiles
│   │   ├── validation.py        # Statement verification (balance, dates)
│   │   ├── result_selection.py  # Candidate selection strategy
│   │   ├── patterns.py          # Unified regex/column header patterns
│   │   ├── classifiers/         # Classification heuristics
│   │   ├── profiles/            # Routing configuration manifests
│   │   └── strategies/          # Modular parsing strategies (table, text, multiline)
│   ├── parsers/                 # Legacy compatibility shims
│   │   ├── csv_parser.py        # Generic CSV with column auto-detection
│   │   ├── llm_parser.py        # Gemini/Ollama LLM fallback
│   │   ├── parser_registry.py   # Registry dispatch shim
│   │   └── base_parser.py       # Base schemas / classes
│   ├── services/
│   │   ├── parser_service.py           # Unified parse orchestration
│   │   ├── transaction_service.py      # UnifiedTransaction CRUD
│   │   ├── category_service.py         # Category CRUD + seed defaults + MCC codes
│   │   ├── categorization_service.py   # Auto-categorization + merchant normalization
│   │   ├── analytics_service.py        # Dashboard aggregation queries
│   │   ├── accounts_service.py         # Account discovery + statement management
│   │   ├── account_resolution_service.py # BankAccount resolve-or-create logic
│   │   ├── statement_audit_service.py  # Statement audit tracking + persistence
│   │   ├── budget_service.py           # Budget CRUD + progress
│   │   ├── goals_service.py            # Savings goal CRUD + contributions
│   │   ├── bill_reminder_service.py    # Reminders + CC auto-detect
│   │   ├── recurring_service.py        # Recurring pattern detection
│   │   ├── transfer_detection_service.py # Transfer auto-detection + manual link/unlink
│   │   ├── upi_service.py              # UPI CRUD + rescan logic
│   │   ├── gdrive_sync_service.py      # Google Drive OAuth sync + parser dispatch
│   │   └── local_sync_service.py       # Local directory sync + parser dispatch
│   ├── utils/
│   │   └── file_utils.py       # Shared file utilities (type inference, review status)
│   └── routers/
│       ├── health.py           # GET /health
│       ├── transactions.py     # Legacy transaction queries
│       ├── upload.py           # v2 unified upload (PDF + CSV)
│       ├── categories.py       # Category CRUD + keywords
│       ├── unified_transactions.py  # v2 transaction queries
│       ├── tags.py             # Tag CRUD
│       ├── analytics.py        # Dashboard analytics
│       ├── accounts.py         # Account/statement management
│       ├── budgets.py          # Budget management
│       ├── goals.py            # Savings goals
│       ├── reminders.py        # Bill reminders + recurring detection
│       ├── export.py           # CSV/JSON export + clear data
│       ├── transfers.py        # Transfer management (detect, link, unlink)
│       ├── upi.py              # UPI ID management (CRUD + rescan)
│       ├── gdrive.py           # Google Drive OAuth (connect, browse, import)
│       ├── admin.py            # Database admin panel (table CRUD)
│       └── local_sync.py       # Local directory sync (scan, import, status)
├── data/                       # SQLite database files
├── requirements.txt
└── Dockerfile
```

### Configuration

All settings are loaded from environment variables or `.env` file via `pydantic-settings`:

| Setting | Default | Description |
|---------|---------|-------------|
| `APP_NAME` | Finance Tracker v2 | Application name |
| `DEBUG` | false | Debug mode |
| `HOST` | 0.0.0.0 | Server bind host |
| `PORT` | 8080 | Server port |
| `DATABASE_URL` | sqlite:///./data/financial-tracker.db | SQLAlchemy connection |
| `MAX_UPLOAD_SIZE_MB` | 10 | Max file upload size |
| `CORS_ORIGINS` | localhost variants | Allowed CORS origins |
| `JWT_SECRET` | `CHANGE-ME-...` | Secret key for JWT signing (must change in production) |
| `JWT_ALGORITHM` | HS256 | JWT signing algorithm |
| `JWT_EXPIRY_MINUTES` | 1440 | Token lifetime (default: 24 hours) |
| `LLM_PROVIDER` | ollama | LLM provider: gemini/ollama/none |
| `GEMINI_API_KEY` | — | Google Gemini API key |
| `GEMINI_MODEL` | gemini-2.0-flash | Gemini model |
| `OLLAMA_MODEL` | lfm2-extract | Ollama model |
| `OLLAMA_HOST` | http://localhost:11434 | Ollama server |
| `GDRIVE_OAUTH_SECRETS_FILE` | credentials_google.json | Path to Google OAuth client secrets JSON |
| `LOCAL_SYNC_PATH` | — | Local folder path for directory sync |
| `LOCAL_SYNC_MAX_FILES` | 500 | Max files returned per scan |
| `LOCAL_SYNC_ALLOWED_ROOTS` | — | Comma-separated allowed root dirs (empty = home + data_dir) |

### Middleware

- **CORS**: Configured via `CORSMiddleware` with configurable origins (defaults to localhost variants)
- **Authentication**: JWT-based single-user auth. All routes (except `/health` and `/api/auth/*` public endpoints) require a valid `Authorization: Bearer <token>` header. Dependency injection via `get_current_user`.
- **Lifespan**: Creates tables on startup, seeds 15 default categories, upgrades keywords, and seeds MCC codes

---

## Frontend

### Directory Structure

```
frontend/lib/
├── main.dart                   # MaterialApp.router with ProviderScope
├── router.dart                 # GoRouter: 5 nav destinations, ShellRoute, NavDestination
├── theme.dart                  # Light/dark ThemeData, page transitions
├── models/
│   ├── credit_card_models.dart
│   ├── savings_models.dart
│   ├── enums.dart
│   ├── unified_transaction_models.dart
│   ├── category_models.dart
│   ├── analytics_models.dart
│   ├── account_models.dart
│   ├── admin_models.dart
│   ├── converters.dart
│   └── upi_models.dart
├── providers/
│   ├── app_settings_provider.dart      # Theme, currency, backend URL
│   ├── statements_provider.dart        # Upload state
│   ├── transactions_provider.dart      # Unified + legacy transaction state
│   ├── categories_provider.dart        # Categories + tags
│   ├── dashboard_provider.dart         # Analytics state
│   ├── dashboard_layout_provider.dart  # Customizable grid layout state (tile config, edit mode)
│   ├── accounts_provider.dart          # Accounts + statements
│   ├── transfers_provider.dart         # Transfer pair state
│   ├── upi_provider.dart               # UPI ID state
│   ├── gdrive_import_provider.dart    # Google Drive OAuth + import state
│   ├── local_sync_provider.dart       # Local directory sync state
│   ├── admin_provider.dart            # Database admin state
│   └── date_range_mixin.dart           # Shared date range mixin
├── screens/
│   ├── app_shell.dart                  # Responsive shell (NavigationRail/Bar)
│   ├── calendar_screen.dart            # Full-page spending calendar with editable transaction popup
│   ├── import_screen.dart              # Import hub: upload + local sync + Google Drive
│   ├── database_manager_screen.dart   # Admin table browser and editor
│   ├── login_screen.dart               # Login/register screen (JWT auth)
│   └── settings_screen.dart            # Settings UI
├── services/
│   ├── api_service.dart                # HTTP client (compatibility facade + barrel export)
│   ├── auth_service.dart               # JWT auth state (login, register, logout, token persistence)
│   └── api/                            # Modular API layer
│       ├── api_client.dart             # Base HTTP client
│       ├── account_api.dart            # Account API methods
│       ├── admin_api.dart              # Admin/database API
│       ├── analytics_api.dart          # Analytics API methods
│       ├── export_api.dart             # Export/data API
│       ├── gdrive_api.dart             # Google Drive OAuth API
│       ├── local_sync_api.dart         # Local directory sync API
│       ├── transaction_api.dart        # Transaction API
│       ├── transfers_api.dart          # Transfer API
│       ├── upload_api.dart             # Upload API
│       └── upi_api.dart               # UPI API
└── widgets/
    ├── dashboard_widget.dart           # Customizable dashboard (grid layout, charts)
    ├── transaction_list_widget.dart     # Legacy savings/CC lists
    ├── unified_transaction_list_widget.dart  # Unified list with filters + editable categories
    ├── accounts_widget.dart            # Account cards → inline filtered transactions
    ├── upi_management_widget.dart      # UPI handle management UI
    ├── skeleton_widgets.dart           # Shimmer loading placeholders
    └── charts/                         # Extracted chart components
        ├── chart_helpers.dart           # Shared chart utilities
        ├── summary_cards.dart          # Dashboard summary cards
        ├── spending_trends_chart.dart   # Spending trends line chart
        ├── category_pie_chart.dart      # Category breakdown pie chart
        ├── income_expense_chart.dart    # Income vs expense bar chart
        ├── month_over_month_card.dart   # MoM comparison
        └── top_merchants_card.dart      # Top merchants list
```

### Navigation (GoRouter)

| Route | Screen/Widget | Description |
|-------|--------------|-------------|
| `/` | DashboardWidget | Customizable grid dashboard: summary, charts, top merchants |
| `/calendar` | CalendarScreen | Full-page spending calendar with daily transaction popup (editable categories) |
| `/import` | ImportScreen | Import hub: file upload, local directory sync, Google Drive sync |
| `/upload` | *(redirect)* | Legacy redirect to `/import` |
| `/accounts` | AccountsWidget | Account cards → click to view filtered transactions inline |
| `/settings` | SettingsScreen | App preferences |

> **Removed routes:** `/transactions`, `/savings`, `/credit-card`, `/budget` were removed from the navigation sidebar. Transactions are now accessed via Account cards or the Calendar popup. Budgets/goals/reminders are managed via the admin panel.

### Responsive Breakpoints

**App Shell Navigation:**

| Width | Layout | Navigation |
|-------|--------|-----------|
| ≥ 900px | Desktop | Expanded NavigationRail (sidebar with labels, 220px) |
| 600–899px | Tablet | Compact NavigationRail (icons + selected label) |
| < 600px | Mobile | Bottom NavigationBar + AppBar |

**Dashboard Grid (ScreenTier):**

| Width | Tier | Behavior |
|-------|------|----------|
| < 600px | Compact | All tiles forced to 12-col (full width), width controls hidden |
| 600–1199px | Medium | Tiles use saved colSpan, side-by-side layout |
| ≥ 1200px | Expanded | Full grid with all resize controls |

---

## Database Schema

**Engine:** SQLite with WAL mode and foreign keys enabled via PRAGMA.
**Tables:** 15+ | **Enums:** 6

### Enums

**TransactionType:** `CREDIT`, `DEBIT`

**BankType:** `HDFC`, `ICICI`, `SBI`, `AXIS`, `KOTAK`, `YES_BANK`, `BOB`, `FEDERAL_BANK`, `OTHER`

**StatementType:** `SAVINGS`, `CREDIT_CARD`, `CURRENT`, `CSV`

**SourceType:** `SAVINGS`, `CREDIT_CARD`

**TransferType:** `INTERNAL_TRANSFER`, `CC_BILL_PAYMENT`

**ReviewStatus:** `AUTO_PARSED`, `LLM_PARSED`, `NEEDS_REVIEW`, `REVIEWED`

### Tables

#### bank_accounts

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| name | String(100) | No | | Display name |
| bank_name | String(30) | No | | BankType value |
| account_type | String(20) | No | | SAVINGS / CREDIT_CARD |
| account_number | String(30) | Yes | | Masked or full |
| holder_name | String(255) | Yes | | Account holder |
| ifsc_code | String(11) | Yes | | IFSC code |
| is_active | Boolean | No | | Default: true |
| created_at | DateTime | No | | Auto-set |

Unique: `(bank_name, account_type, account_number)`
Has many: `statement_audit`

#### statement_audit

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| file_name | String(500) | No | | Original filename |
| file_hash | String(64) | Yes | IDX | SHA-256 hash |
| file_size_bytes | Integer | Yes | | File size |
| bank_account_id | Integer | Yes | FK | → bank_accounts.id |
| bank_name | String(30) | Yes | | Denormalized for failed imports |
| statement_type | String(20) | No | | SAVINGS/CREDIT_CARD |
| period_start | Date | Yes | | Statement start date |
| period_end | Date | Yes | | Statement end date |
| opening_balance | Numeric(15,2) | Yes | | |
| closing_balance | Numeric(15,2) | Yes | | |
| due_date | Date | Yes | | CC-specific |
| credit_limit | Numeric(15,2) | Yes | | CC-specific |
| available_credit | Numeric(15,2) | Yes | | CC-specific |
| minimum_amount_due | Numeric(15,2) | Yes | | CC-specific |
| account_holder_name | String(255) | Yes | | Savings-specific |
| card_holder_name | String(255) | Yes | | CC-specific |
| account_number | String(30) | Yes | | |
| card_number | String(20) | Yes | | |
| ifsc_code | String(11) | Yes | | |
| branch_name | String(255) | Yes | | |
| parser_strategy | String(50) | Yes | | e.g., table_extraction, text_lines, llm |
| transaction_count | Integer | No | | Default: 0 |
| status | String(20) | No | IDX | SUCCESS/FAILED/SKIPPED |
| error_message | Text | Yes | | Error details for failed imports |
| source | String(20) | No | | upload / local_sync / gdrive_oauth |
| imported_at | DateTime | No | | Auto-set |

Unique: `(bank_account_id, period_start, period_end)`

#### mcc_categories

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| mcc_code | String(4) | No | UK | 4-digit Merchant Category Code |
| description | String(200) | Yes | | MCC description |
| category_id | Integer | No | FK | → categories.id |

#### credit_card_statements

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| statement_date | Date | Yes | | |
| due_date | Date | Yes | | |
| card_number | String(20) | Yes | | |
| card_holder_name | String(255) | Yes | | |
| credit_limit | Numeric(15,2) | Yes | | |
| available_credit | Numeric(15,2) | Yes | | |
| total_dues | Numeric(15,2) | Yes | | |
| minimum_amount_due | Numeric(15,2) | Yes | | |

Unique: `(card_number, statement_date)`
Has many: `credit_card_transactions`

#### credit_card_transactions

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| date | Date | Yes | | |
| description | String(500) | Yes | | |
| amount | Numeric(15,2) | Yes | | |
| type | Enum(TransactionType) | Yes | | CREDIT/DEBIT |
| reference_number | String(100) | Yes | | |
| statement_id | Integer | Yes | FK | → credit_card_statements.id |

#### savings_account_statements

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| account_number | String(20) | Yes | | |
| account_holder_name | String(255) | Yes | | |
| ifsc_code | String(11) | Yes | | |
| branch_name | String(255) | Yes | | |
| from_date | Date | Yes | | |
| to_date | Date | Yes | | |
| opening_balance | Numeric(15,2) | Yes | | |
| closing_balance | Numeric(15,2) | Yes | | |

Unique: `(account_number, from_date, to_date)`
Has many: `savings_account_transactions`

#### savings_account_transactions

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| date | Date | Yes | | |
| description | String(500) | Yes | | |
| reference_number | String(100) | Yes | | |
| withdrawal_amount | Numeric(15,2) | Yes | | |
| deposit_amount | Numeric(15,2) | Yes | | |
| closing_balance | Numeric(15,2) | Yes | | |
| type | Enum(TransactionType) | Yes | | CREDIT/DEBIT |
| statement_id | Integer | Yes | FK | → savings_account_statements.id |

#### unified_transactions

The core denormalized table. Every transaction from any source ends up here.

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| date | Date | Yes | | |
| description | String(500) | Yes | | |
| amount | Numeric(15,2) | Yes | | Always positive; direction via `type` |
| type | Enum(TransactionType) | Yes | | CREDIT/DEBIT |
| source_type | Enum(SourceType) | **No** | | SAVINGS/CREDIT_CARD |
| source_transaction_id | Integer | **No** | | ID in the source table |
| bank | String(30) | Yes | | |
| account_identifier | String(30) | Yes | | |
| category_id | Integer | Yes | FK | → categories.id |
| merchant_name | String(200) | Yes | | Normalized merchant name |
| notes | Text | Yes | | User notes |
| reference_number | String(100) | Yes | | |
| created_at | DateTime | **No** | | Default: UTC now |

Unique: `(source_type, source_transaction_id)`
Belongs to: `categories`
Many-to-many: `tags` via `transaction_tags`

##### Transfer-Related Columns

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| is_transfer | Boolean | No | | Default: false |
| transfer_group_id | String(36) | Yes | IDX | UUID linking transfer pairs |
| transfer_type | Enum(TransferType) | Yes | | INTERNAL_TRANSFER/CC_BILL_PAYMENT |
| review_status | String(20) | Yes | | AUTO_PARSED/NEEDS_REVIEW/etc. |
| review_reason | String(500) | Yes | | Reason why it needs review |

#### categories

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| name | String(100) | **No** | UQ | Unique name |
| icon | String(50) | Yes | | Material icon name |
| color | String(7) | Yes | | Hex color (#FF5722) |
| parent_id | Integer | Yes | FK | → categories.id (self-referencing) |
| is_system | Boolean | | | Default: true |

Has many: `category_keywords`, `children` (self), `unified_transactions`, `budgets`

#### category_keywords

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| keyword | String(100) | **No** | UQ | Unique keyword |
| category_id | Integer | **No** | FK | → categories.id |

#### tags

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| name | String(50) | **No** | UQ | Unique name |
| color | String(7) | Yes | | Hex color |

#### transaction_tags (junction)

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| transaction_id | Integer | No | PK (composite) | → unified_transactions.id, CASCADE |
| tag_id | Integer | No | PK (composite) | → tags.id, CASCADE |

#### budgets

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| category_id | Integer | **No** | FK | → categories.id |
| year | Integer | **No** | | |
| month | Integer | **No** | | 1–12 |
| amount | Numeric(15,2) | **No** | | |
| rollover | Boolean | | | Default: false |
| notes | Text | Yes | | |
| created_at | DateTime | | | Default: UTC now |

Unique: `(year, month, category_id)`

#### savings_goals

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| name | String(200) | **No** | | |
| target_amount | Numeric(15,2) | **No** | | |
| current_amount | Numeric(15,2) | | | Default: 0 |
| deadline | Date | Yes | | |
| icon | String(50) | Yes | | |
| color | String(7) | Yes | | |
| notes | Text | Yes | | |
| is_completed | Boolean | | | Default: false |
| created_at | DateTime | | | Default: UTC now |

#### bill_reminders

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| name | String(200) | **No** | | |
| amount | Numeric(15,2) | Yes | | |
| category_id | Integer | Yes | FK | → categories.id |
| is_recurring | Boolean | | | Default: true |
| frequency | String(20) | Yes | | MONTHLY/QUARTERLY/YEARLY |
| day_of_month | Integer | Yes | | 1–31 |
| next_due_date | Date | Yes | | |
| is_auto_detected | Boolean | | | Default: false |
| is_paid | Boolean | | | Default: false |
| notes | Text | Yes | | |
| created_at | DateTime | | | Default: UTC now |

#### recurring_transactions

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| merchant_name | String(200) | **No** | | |
| description_pattern | String(500) | Yes | | |
| average_amount | Numeric(15,2) | **No** | | |
| frequency | String(20) | **No** | | WEEKLY/MONTHLY/QUARTERLY/YEARLY |
| category_id | Integer | Yes | FK | → categories.id |
| last_date | Date | Yes | | |
| next_expected_date | Date | Yes | | |
| occurrence_count | Integer | | | Default: 0 |
| is_active | Boolean | | | Default: true |
| is_subscription | Boolean | | | Default: false |
| created_at | DateTime | | | Default: UTC now |

#### upi_ids

| Column | Type | Nullable | Key | Notes |
|--------|------|----------|-----|-------|
| id | Integer | No | PK | Auto-increment |
| upi_handle | String(100) | **No** | UQ, IDX | Unique UPI handle (e.g. user@bank) |
| label | String(200) | Yes | | Friendly name |
| account_type | String(20) | Yes | | Account type (for own UPIs) |
| account_identifier | String(30) | Yes | | Linked account/card number |
| category_id | Integer | Yes | FK | → categories.id (for auto-categorization) |
| is_own | Boolean | **No** | | Default: false (true = user's own UPI) |
| created_at | DateTime | **No** | | Default: UTC now |

### Entity Relationship Diagram

```
credit_card_statements 1───* credit_card_transactions
savings_account_statements 1───* savings_account_transactions

categories 1───* category_keywords
categories 1───* categories (self via parent_id)
categories 1───* unified_transactions
categories 1───* budgets
categories 1───* bill_reminders
categories 1───* recurring_transactions
categories 1───* upi_ids

unified_transactions *───* tags (via transaction_tags)
```

---

## API Specification

**Base URL:** `http://localhost:8080`
**API Docs:** `/docs` (Swagger UI), `/redoc` (ReDoc), `/v3/api-docs` (OpenAPI JSON)

### Endpoint Count by Domain

| Domain | Count | Prefix |
|--------|:-----:|--------|
| Health | 1 | `/health` |
| Authentication | 4 | `/api/auth/` |
| Legacy Transactions | 3 | `/api/transactions` |
| Upload (v2) | 3 | `/api/v2/statements/` |
| Categories | 7 | `/api/v2/categories/` |
| Unified Transactions | 8 | `/api/v2/transactions/` |
| Tags | 3 | `/api/v2/tags/` |
| Analytics | 7 | `/api/v2/analytics/` |
| Accounts | 5 | `/api/v2/accounts/` |
| Budgets | 7 | `/api/v2/budgets/` |
| Savings Goals | 6 | `/api/v2/goals/` |
| Reminders | 6 | `/api/v2/reminders/` |
| Recurring | 4 | `/api/v2/recurring/` |
| Export | 2 | `/api/v2/export/` |
| Data (Clear) | 1 | `/api/v2/data/` |
| Google Drive (OAuth) | 12 | `/api/v2/gdrive/` |
| Transfers | 5 | `/api/v2/transfers/` |
| UPI IDs | 7 | `/api/v2/upi-ids/` |
| Local Directory Sync | 6 | `/api/v2/local-sync/` |
| Admin / Database | 7+ | `/api/v2/admin/` |
| **Total** | **~122** | |

> See [FLOW.md](FLOW.md) for the complete endpoint reference with parameters and descriptions.

---

## Parsers

### Parser Registry

The system uses a registry pattern: `(BankType, StatementType)` → parser class.

| Bank | Type | Parser | Method |
|------|------|--------|--------|
| Any | SAVINGS | `GenericPdfParser` | Table extraction + text fallback |
| Any | CREDIT_CARD | `GenericPdfParser` | Table extraction + text fallback |
| Any | Any | `LLMParser` | Gemini/Ollama (fallback, optional) |
| Any | CSV | `CsvParser` | Column auto-detection |

### Generic PDF Parser

A bank-agnostic PDF parser that uses template classification and routing to try multiple heuristic parsing strategies in sequence. Successful strategy parses are evaluated, and the best-fitting parse result (typically the one with the highest transaction count) is selected.

*   **Strategy 1 — Table Extraction:** Uses bounding-box coordinate math from `pdfplumber` to extract structured grids. Best for clean tabular PDFs (e.g., Federal Bank).
*   **Strategy 2 — Single-Line Text Parsing:** Processes lines sequentially to find leading dates and trailing amounts. Best for simple one-transaction-per-line layouts.
*   **Strategy 3a — Credit Card Multi-Line:** Matches date-time headers and collects multi-line descriptions until a currency-prefixed amount is found. Target: Modern HDFC Credit Cards.
*   **Strategy 3b — Credit Card Simple Multi-Line:** Buffers lines following a date until a bare numeric amount is matched. Target: Older HDFC Credit Cards and UPI Credit Cards.
*   **Strategy 4 — Generic Multi-Line Text:** Reassembles vertically wrapped transaction blocks (serial, date, description, debit, credit, balance on separate lines). Target: Bank of Baroda.

### LLM Fallback Parser (optional)

If the generic parser fails, the system can send the raw PDF text to an LLM (Gemini or Ollama) with a structured prompt requesting JSON output. Disabled by default (`LLM_PROVIDER=none`).

### CSV Parser

Auto-detects columns by matching header names: Date, Description, Debit, Credit, Balance, Reference. Supports comma, tab, semicolon, and pipe delimiters.

---

## Auto-Categorization

### Process

1. On statement upload → unified transactions are created
2. Each transaction description is matched against category keywords
3. Longest-match wins (e.g., "AMAZON PRIME" matches "AMAZON PRIME" before "AMAZON")
4. Merchant name is normalized: UPI/NEFT/IMPS prefixes stripped, reference numbers removed

### Default Categories (15)

Food & Dining, Transport, Shopping, Bills & Utilities, Entertainment, Health, Travel, Education, Transfers, Salary, Investment, ATM/Cash, EMI/Loan, Insurance, Other

Each has pre-configured keywords. Users can add custom categories and keywords.

---

## Deployment

### Docker Compose

```yaml
services:
  backend:
    build: ./backend
    ports: ["8080:8080"]
    volumes: [finance-data:/app/data]
    environment:
      DATABASE_URL: sqlite:///./data/finance_tracker.db
      CORS_ORIGINS: http://localhost:3000
      JWT_SECRET: ${JWT_SECRET:-CHANGE-ME-set-JWT_SECRET-env-var}

  frontend:
    build: ./frontend
    ports: ["3000:80"]
    depends_on:
      backend: { condition: service_healthy }
```

Frontend is built with Flutter and served via nginx. Backend runs uvicorn behind Docker.

### Local Development

**Backend:** `uvicorn app.main:app --port 8080 --reload`
**Frontend (Web):** `flutter run -d chrome --web-port 3000`
**Frontend (Windows):** `flutter run -d windows`

---

## Migration History

This app was migrated from Java/Spring Boot + React to Python/FastAPI + Flutter.

| Aspect | v1 (Java) | v2 (Python/Flutter) |
|--------|-----------|---------------------|
| Backend | Java 17, Spring Boot 3.2 | Python 3.12+, FastAPI 0.115 |
| ORM | JPA/Hibernate | SQLAlchemy 2.0 |
| Database | H2 (in-memory) | SQLite (persistent, WAL) |
| PDF | Apache PDFBox | pdfplumber |
| Frontend | React 18 + TypeScript | Flutter 3.x + Dart |
| Build | Gradle (5 modules) | pip + flutter CLI |
| LOC (Backend) | ~2,025 | ~1,200 |
| LOC (Frontend) | ~215 | ~600 |

### Bugs Fixed During Migration

1. **CORS not configured** — Added CORSMiddleware
2. **No unique constraints** — Added upsert logic for duplicate statement uploads
3. **JPA JSON recursion** — Pydantic DTOs eliminate bidirectional entity issues
4. **Upload size mismatch** — Single configurable limit (10MB)
5. **Hardcoded year fallback** — Uses `datetime.now().year`
6. **Missing CC transaction query** — Added endpoint
7. **System.out.println** — Replaced with structured logging

---

## Future Enhancements

### Phase 7: Security, Integrations & Deployment (In Progress)

| Task | Description | Status |
|------|-------------|--------|
| Authentication | Single-user JWT auth (bcrypt + HS256). Register/login endpoints. Token persistence via SharedPreferences on frontend | ✅ Done |
| Google Drive Sync (OAuth2) | Import statements from personal Google Drive via OAuth2. Folder browsing, bank/type mappings, background import with job tracking, 12 API endpoints | ✅ Done |
| Data encryption | AES-256 encryption for account/card numbers at rest | Planned |
| PostgreSQL option | Switch from SQLite to PostgreSQL for multi-device access | Planned |
| Backup/Restore | One-click DB backup and restore with download/upload | Planned |

### Phase 8: Customizable Dashboard & Calendar (Completed)

| Task | Description | Status |
|------|-------------|--------|
| Spending calendar | Bank-wise heatmap calendar with per-day color-coded breakdown using LinearGradient | ✅ Done |
| Configurable grid layout | 12-column responsive grid with per-tile colSpan (snap stops: 4/6/8/12) and height (40px steps) | ✅ Done |
| Tile controls | Reorder (↑↓), visibility toggle, width (◀▶) and height (▲▼) resize buttons | ✅ Done |
| Responsive breakpoints | ScreenTier (compact/medium/expanded) — compact forces all tiles full-width | ✅ Done |
| Layout persistence | Dashboard layout saved to SharedPreferences, restored on reload | ✅ Done |
| Smooth animations | AnimatedContainer for size transitions, AnimatedOpacity for visibility | ✅ Done |

### Phase 9: Accounts & Transactions Refactor (Completed)

| Task | Description | Status |
|------|-------------|--------|
| Calendar as standalone page | Full-page spending calendar with clickable days showing transaction popup with editable categories | ✅ Done |
| Account-centric transactions | Click account card → view filtered transactions inline. Backend `account_identifier` filter added | ✅ Done |
| Simplified navigation | Removed standalone Transactions/Savings/Credit Card sidebar tabs. Added Calendar | ✅ Done |
| Editable categories everywhere | Category chips on transaction tiles in Calendar popup and Account transactions. Tap to change | ✅ Done |

### Phase 10: Transfer Detection & UPI ID Management (Completed)

| Task | Description | Status |
|------|-------------|--------|
| Transfer detection | Auto-detect DEBIT/CREDIT pairs across accounts. Manual link/unlink. TransferType enum (INTERNAL_TRANSFER, CC_BILL_PAYMENT) | ✅ Done |
| UPI ID management | Map UPI handles to accounts/categories. Auto-categorize and flag transfers. CRUD + rescan endpoints | ✅ Done |
| Dashboard widget split | Extracted chart widgets into `widgets/charts/` subdirectory | ✅ Done |
| API service decomposition | Split `api_service.dart` into `services/api/` modular directory | ✅ Done |

### Potential Features

| Feature | Description |
|---------|-------------|
| Multi-user support | Separate data per user with login system |
| Bank API integration | Direct bank feeds via Account Aggregator/Open Banking |
| Mobile app | Android/iOS builds (Flutter already supports them) |
| Notifications | Push alerts for bill reminders and budget overruns |
| AI insights | LLM-powered spending advice and anomaly detection |
| Receipt scanning | OCR for paper receipts |
| Investment tracking | Mutual funds, stocks, FDs portfolio view |
| Net worth dashboard | Aggregated view across all accounts and investments |
| Shared expenses | Split tracking with family members |
| Tax reporting | Annual tax-relevant transaction summary |
