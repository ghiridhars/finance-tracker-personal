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
│  │ (8 routes)│  │ (State)  │  │ (Material 3)│           │
│  └──────────┘  └──────────┘  └────────────┘            │
│               ↕ HTTP (REST JSON)                        │
├─────────────────────────────────────────────────────────┤
│                     Backend                              │
│           Python 3.11+ / FastAPI 0.115                  │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐            │
│  │ Routers  │  │ Services │  │  Parsers   │            │
│  │ (15 mods)│  │ (logic)  │  │ (PDF/CSV)  │            │
│  └──────────┘  └──────────┘  └────────────┘            │
│               ↕ SQLAlchemy ORM                          │
├─────────────────────────────────────────────────────────┤
│                    Database                              │
│          SQLite (WAL mode, foreign keys)                │
│            12 tables, 4 enums                           │
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
| Language | Python | 3.11+ |
| Framework | FastAPI | 0.115.0 |
| ASGI Server | Uvicorn | 0.30.6 |
| ORM | SQLAlchemy | 2.0.35 |
| Migrations | Alembic | 1.13.1 |
| Validation | Pydantic | 2.9.2 |
| Settings | pydantic-settings | 2.5.2 |
| PDF Parsing | pdfplumber | 0.11.4 |
| LLM (Gemini) | google-genai | ≥1.0.0 |
| LLM (Ollama) | ollama | ≥0.4.0 |
| Logging | loguru | 0.7.2 |
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
│   │   ├── enums.py            # TransactionType, BankType, StatementType, SourceType
│   │   ├── credit_card.py      # CreditCardStatement, CreditCardTransaction
│   │   ├── savings_account.py  # SavingsAccountStatement, SavingsAccountTransaction
│   │   ├── transaction.py      # UnifiedTransaction (denormalized)
│   │   ├── category.py         # Category, CategoryKeyword
│   │   ├── tag.py              # Tag, TransactionTag
│   │   └── budget.py           # Budget, SavingsGoal, BillReminder, RecurringTransaction
│   ├── schemas/
│   │   ├── common.py           # ApiError
│   │   ├── credit_card.py      # Credit card DTOs
│   │   ├── savings_account.py  # Savings DTOs
│   │   ├── category.py         # Category CRUD DTOs
│   │   ├── tag.py              # Tag DTOs
│   │   ├── transaction.py      # UnifiedTransaction query/update DTOs
│   │   └── budget.py           # Budget, Goal, Reminder, Recurring DTOs
│   ├── parsers/
│   │   ├── base_parser.py      # ABC + pdfplumber integration
│   │   ├── generic_pdf_parser.py # Bank-agnostic PDF parser (table + text)
│   │   ├── csv_parser.py       # Generic CSV with column auto-detection
│   │   ├── llm_parser.py       # Gemini/Ollama LLM fallback
│   │   └── parser_registry.py  # (BankType, StatementType) → parser dispatch
│   ├── services/
│   │   ├── parser_service.py   # Unified parse orchestration
│   │   ├── credit_card_service.py
│   │   ├── savings_service.py
│   │   ├── transaction_service.py      # UnifiedTransaction CRUD
│   │   ├── category_service.py         # Category CRUD + seed defaults
│   │   ├── categorization_service.py   # Auto-categorization + merchant normalization
│   │   ├── analytics_service.py        # Dashboard aggregation queries
│   │   ├── accounts_service.py         # Account discovery + statement management
│   │   ├── budget_service.py           # Budget CRUD + progress
│   │   ├── goals_service.py            # Savings goal CRUD + contributions
│   │   ├── bill_reminder_service.py    # Reminders + CC auto-detect
│   │   ├── recurring_service.py        # Recurring pattern detection
│   │   └── gdrive_sync_service.py      # Google Drive file sync + parser dispatch
│   └── routers/
│       ├── health.py           # GET /health
│       ├── parse.py            # Parse-only endpoints
│       ├── credit_card.py      # Credit card CRUD
│       ├── statements.py       # Legacy upload
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
│       └── gdrive.py           # Google Drive sync (status, files, sync, reset)
├── alembic/                    # Migration configs
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
| `LLM_PROVIDER` | gemini | LLM provider: gemini/ollama/none |
| `GEMINI_API_KEY` | — | Google Gemini API key |
| `GEMINI_MODEL` | gemini-2.0-flash | Gemini model |
| `OLLAMA_MODEL` | llama3.2 | Ollama model |
| `OLLAMA_HOST` | http://localhost:11434 | Ollama server |
| `GDRIVE_ENABLED` | false | Enable Google Drive sync |
| `GDRIVE_CREDENTIALS_FILE` | — | Path to service account JSON key |
| `GDRIVE_FOLDER_ID` | — | Google Drive folder to watch |
| `GDRIVE_POLL_INTERVAL_MINUTES` | 60 | Auto-sync interval (0 = manual only) |

### Middleware

- **CORS**: Configured via `CORSMiddleware` with configurable origins (defaults to localhost variants)
- **Authentication**: JWT-based single-user auth. All routes (except `/health` and `/api/auth/*` public endpoints) require a valid `Authorization: Bearer <token>` header. Dependency injection via `get_current_user`.
- **Lifespan**: Creates tables on startup, seeds 15 default categories

---

## Frontend

### Directory Structure

```
frontend/lib/
├── main.dart                   # MaterialApp.router with ProviderScope
├── router.dart                 # GoRouter: 8 routes, ShellRoute, NavDestination
├── theme.dart                  # Light/dark ThemeData, page transitions
├── models/
│   ├── credit_card_models.dart
│   ├── savings_models.dart
│   ├── enums.dart
│   ├── unified_transaction_models.dart
│   ├── category_models.dart
│   ├── analytics_models.dart
│   ├── account_models.dart
│   └── budget_models.dart
├── providers/
│   ├── app_settings_provider.dart      # Theme, currency, backend URL
│   ├── statements_provider.dart        # Upload state
│   ├── transactions_provider.dart      # Unified + legacy transaction state
│   ├── categories_provider.dart        # Categories + tags
│   ├── dashboard_provider.dart         # Analytics state
│   ├── accounts_provider.dart          # Accounts + statements
│   └── budget_provider.dart            # Budgets, goals, reminders, recurring
├── screens/
│   ├── app_shell.dart                  # Responsive shell (NavigationRail/Bar)
│   ├── login_screen.dart               # Login/register screen (JWT auth)
│   ├── home_screen.dart                # Legacy tab layout (unused)
│   └── settings_screen.dart            # Settings UI
├── services/
│   ├── api_service.dart                # HTTP client (all API methods, auth token injection)
│   └── auth_service.dart               # JWT auth state (login, register, logout, token persistence)
└── widgets/
    ├── statement_upload_widget.dart     # Upload with drop zone
    ├── transaction_list_widget.dart     # Legacy savings/CC lists
    ├── unified_transaction_list_widget.dart  # Unified list with filters
    ├── dashboard_widget.dart           # Charts + summary cards
    ├── accounts_widget.dart            # Account management
    ├── budget_goals_widget.dart        # Budgets, goals, reminders
    └── skeleton_widgets.dart           # Shimmer loading placeholders
```

### Navigation (GoRouter)

| Route | Screen/Widget | Description |
|-------|--------------|-------------|
| `/` | DashboardWidget | Summary cards, charts |
| `/upload` | StatementUploadWidget | PDF/CSV upload |
| `/transactions` | UnifiedTransactionListWidget | Searchable transaction list |
| `/accounts` | AccountsWidget | Account & statement management |
| `/budget` | BudgetGoalsWidget | Budgets, goals, reminders |
| `/savings` | TransactionListWidget (savings) | Legacy savings view |
| `/credit-card` | TransactionListWidget (credit card) | Legacy CC view |
| `/settings` | SettingsScreen | App preferences |

### Responsive Breakpoints

| Width | Layout | Navigation |
|-------|--------|-----------|
| ≥ 900px | Desktop | Expanded NavigationRail (sidebar with labels, 220px) |
| 600–899px | Tablet | Compact NavigationRail (icons + selected label) |
| < 600px | Mobile | Bottom NavigationBar + AppBar |

---

## Database Schema

**Engine:** SQLite with WAL mode and foreign keys enabled via PRAGMA.
**Tables:** 12 | **Enums:** 4

### Enums

**TransactionType:** `CREDIT`, `DEBIT`

**BankType:** `HDFC`, `ICICI`, `SBI`, `AXIS`, `KOTAK`, `YES_BANK`, `BOB`, `FEDERAL_BANK`, `OTHER`

**StatementType:** `SAVINGS`, `CREDIT_CARD`, `CURRENT`, `CSV`

**SourceType:** `SAVINGS`, `CREDIT_CARD`

### Tables

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
| Parsing | 1 | `/api/parse/` |
| Credit Card | 3 | `/api/credit-card/` |
| Savings | 1 | `/api/statements/` |
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
| Export/Data | 2 | `/api/v2/export/`, `/api/v2/data/` |
| Google Drive Sync | 4 | `/api/v2/gdrive/` |
| **Total** | **75** | |

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

Bank-agnostic parser with two extraction strategies (tried in order):

**Strategy 1 — Table extraction:**
- Uses pdfplumber `extract_tables()` to detect structured tables in PDFs
- Auto-detects column headers (Date, Description/Narration/Particulars, Debit/Withdrawal, Credit/Deposit, Balance, Reference/Tran ID)
- Works for banks with clean table formatting (e.g., Federal Bank)

**Strategy 2 — Text-based line parsing:**
- Detects transaction lines by finding leading dates and trailing amounts
- Classifies amounts into debit, credit, and balance columns
- Handles continuation lines (multi-line descriptions)
- Works for banks where table extraction produces merged columns (e.g., Bank of Baroda)

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
| Backend | Java 17, Spring Boot 3.2 | Python 3.11+, FastAPI 0.115 |
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
| Google Drive Sync | Auto-import statements from Google Drive via service account. File type inference, sync state tracking, 4 API endpoints | ✅ Done |
| Data encryption | AES-256 encryption for account/card numbers at rest | Planned |
| PostgreSQL option | Switch from SQLite to PostgreSQL for multi-device access | Planned |
| Backup/Restore | One-click DB backup and restore with download/upload | Planned |

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
