# Finance Tracker v2 — Migration Documentation

## Overview

Complete rewrite of the **Finance Tracker** personal finance management application from Java/Spring Boot + React to **Python/FastAPI** backend + **Flutter Web** frontend.

---

## Migration Summary

| Aspect | v1 (Java) | v2 (Python + Flutter) |
|---|---|---|
| **Backend Language** | Java 17 | Python 3.11+ |
| **Framework** | Spring Boot 3.2.1 | FastAPI 0.115.0 |
| **ORM** | JPA / Hibernate | SQLAlchemy 2.0.35 |
| **Database** | H2 (in-memory) | SQLite (persistent) |
| **PDF Parsing** | Apache PDFBox 2.0.29 | pdfplumber 0.11.4 |
| **Frontend Framework** | React 18 + TypeScript | Flutter 3.x (Web) |
| **Build System** | Gradle multi-module (5 modules) | pip + Flutter CLI |
| **API Docs** | SpringDoc (manual) | FastAPI auto-generated Swagger |
| **LOC (Backend)** | ~2,025 Java | ~1,200 Python |
| **LOC (Frontend)** | ~215 React/TS | ~600 Dart/Flutter |

---

## Architecture

```
finance-tracker-v2/
├── backend/                    # Python FastAPI backend
│   ├── app/
│   │   ├── main.py             # App entry point, CORS, routers
│   │   ├── config.py           # Settings (env-based)
│   │   ├── database.py         # SQLAlchemy engine + session
│   │   ├── models/             # SQLAlchemy ORM models
│   │   │   ├── enums.py        # TransactionType enum
│   │   │   ├── credit_card.py  # CreditCardStatement + Transaction
│   │   │   └── savings_account.py  # SavingsAccountStatement + Transaction
│   │   ├── schemas/            # Pydantic DTOs
│   │   │   ├── common.py       # ApiError
│   │   │   ├── credit_card.py  # Credit card schemas
│   │   │   └── savings_account.py  # Savings schemas
│   │   ├── parsers/            # PDF parsing logic
│   │   │   ├── base_parser.py  # ABC + pdfplumber integration
│   │   │   ├── hdfc_credit_card_parser.py
│   │   │   └── hdfc_savings_parser.py
│   │   ├── services/           # Business logic
│   │   │   ├── credit_card_service.py
│   │   │   ├── savings_service.py
│   │   │   └── parser_service.py
│   │   └── routers/            # API endpoints
│   │       ├── health.py       # GET /health
│   │       ├── parse.py        # POST /api/parse/*
│   │       ├── credit_card.py  # Credit card CRUD
│   │       ├── statements.py   # Unified upload endpoint
│   │       └── transactions.py # Transaction queries
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/                   # Flutter Web frontend
│   ├── lib/
│   │   ├── main.dart           # App entry + Material theme
│   │   ├── models/             # Data models with fromJson
│   │   ├── services/           # API service (http package)
│   │   ├── screens/            # HomeScreen (tabbed layout)
│   │   └── widgets/            # Upload + Transaction list widgets
│   ├── Dockerfile
│   └── nginx.conf
└── docker-compose.yml          # Orchestrates backend + frontend
```

---

## API Endpoints

All endpoints are backward-compatible with v1 where applicable.

| Method | Path | Description | Changes from v1 |
|---|---|---|---|
| `GET` | `/health` | Health + DB check | Now checks SQLite connectivity |
| `POST` | `/api/parse/hdfc-credit-card` | Parse credit card PDF (no save) | Same behavior |
| `POST` | `/api/credit-card/statements/upload` | Parse + save credit card | Same behavior |
| `GET` | `/api/credit-card/statements/{card_number}` | Get by card number | Same behavior |
| `GET` | `/api/credit-card/statements` | Query by date range | Same behavior |
| `POST` | `/api/statements/upload` | Unified upload (bank param) | Same behavior |
| `GET` | `/api/transactions` | All savings transactions | Same (backward-compat) |
| `GET` | `/api/transactions/savings` | Savings transactions | Same behavior |
| `GET` | `/api/transactions/credit-card` | Credit card transactions | **NEW** — missing in v1 |

---

## Bugs Fixed During Migration

### 1. CORS Not Configured
- **v1 Bug**: No CORS headers sent; frontend requests from `localhost:3000` would fail.
- **v2 Fix**: `CORSMiddleware` added in `main.py` with configurable origins via `CORS_ORIGINS` env var.

### 2. No Unique Constraints on Statements
- **v1 Bug**: Re-uploading the same PDF created duplicate records.
- **v2 Fix**: `UniqueConstraint("card_number", "statement_date")` on credit card statements, `UniqueConstraint("account_number", "from_date", "to_date")` on savings statements. Service layer uses upsert logic.

### 3. JPA Entity JSON Recursion
- **v1 Bug**: Controllers returned JPA entities with bidirectional `@ManyToOne`/`@OneToMany` → infinite JSON recursion unless `@JsonIgnore` was perfect.
- **v2 Fix**: All endpoints return Pydantic schemas (DTOs). Models and schemas are separate — no recursion possible.

### 4. Upload Size Limit Mismatch
- **v1 Bug**: Spring Boot default 1MB multipart limit vs `ParserService.MAX_FILE_SIZE = 10MB` → confusing errors.
- **v2 Fix**: Single `MAX_UPLOAD_SIZE = 10MB` in `config.py`, validated in `ParserService` before parsing.

### 5. Hardcoded Year Fallback
- **v1 Bug**: `HdfcCreditCardPdfParser` used `2023` as fallback year when header date wasn't found.
- **v2 Fix**: Uses `datetime.now().year` as fallback.

### 6. Missing Credit Card Transaction Query
- **v1 Bug**: `TransactionController` only had a savings transaction endpoint. No way to query credit card transactions.
- **v2 Fix**: Added `GET /api/transactions/credit-card` endpoint.

### 7. System.out.println Instead of Logging
- **v1 Bug**: Parsers used `System.out.println()` for debug output.
- **v2 Fix**: Uses `loguru` throughout with structured logging.

---

## Parser Port Details

Both HDFC parsers were ported 1:1 with exact regex pattern preservation:

### HDFC Savings Parser
- 10+ regex patterns for header extraction (account number, IFSC, branch, dates)
- Transaction line pattern: `dd/mm/yy description ref amount balance`
- Reference number heuristic: excludes BLOCK, REV, CWDR patterns
- Opening balance calculation from first transaction

### HDFC Credit Card Parser
- Statement date, due date, card number extraction
- Card holder name, credit limit, available credit
- Total dues and minimum amount due
- Transaction line parsing with date + description + amount
- Debit/credit classification based on Cr suffix

---

## How to Run

### Backend (Development)

```bash
cd finance-tracker-v2/backend
python -m venv .venv

# Windows
.\.venv\Scripts\Activate.ps1

# Linux/Mac
source .venv/bin/activate

pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
```

- Swagger UI: http://localhost:8080/docs
- Health: http://localhost:8080/health

### Frontend (Development)

```bash
cd finance-tracker-v2/frontend
flutter pub get
flutter run -d chrome
```

### Docker (Production)

```bash
cd finance-tracker-v2
docker-compose up --build
```

- Frontend: http://localhost:3000
- Backend API: http://localhost:8080

---

## Validation Results

- ✅ All Python imports resolve correctly
- ✅ FastAPI server starts without errors
- ✅ `GET /health` returns `{"status": "UP", "database": true}`
- ✅ `GET /api/transactions/savings` returns `[]` (empty DB)
- ✅ Swagger UI accessible at `/docs`
- ✅ SQLite database auto-created with proper schema
- ✅ Flutter project compiles (dependencies resolved)

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `sqlite:///./data/finance_tracker.db` | SQLAlchemy connection string |
| `CORS_ORIGINS` | `http://localhost:3000,...` | Comma-separated allowed origins |
| `MAX_UPLOAD_SIZE` | `10485760` (10 MB) | Max PDF upload size in bytes |

---

## File Mapping (v1 → v2)

| Java (v1) | Python (v2) |
|---|---|
| `TransactionType.java` | `app/models/enums.py` |
| `CreditCardStatement.java` | `app/models/credit_card.py` |
| `CreditCardTransaction.java` | `app/models/credit_card.py` |
| `SavingsAccountStatement.java` | `app/models/savings_account.py` |
| `SavingsAccountTransaction.java` | `app/models/savings_account.py` |
| `CreditCardStatementDto.java` | `app/schemas/credit_card.py` |
| `SavingsAccountStatementDto.java` | `app/schemas/savings_account.py` |
| `PdfBoxStatementParser.java` | `app/parsers/base_parser.py` |
| `HdfcCreditCardPdfParser.java` | `app/parsers/hdfc_credit_card_parser.py` |
| `HdfcSavingsPdfParser.java` | `app/parsers/hdfc_savings_parser.py` |
| `CreditCardStatementService.java` | `app/services/credit_card_service.py` |
| `SavingsAccountStatementService.java` | `app/services/savings_service.py` |
| `ParserService.java` | `app/services/parser_service.py` |
| `HealthCheckController.java` | `app/routers/health.py` |
| `ParseController.java` | `app/routers/parse.py` |
| `CreditCardStatementController.java` | `app/routers/credit_card.py` |
| `StatementController.java` | `app/routers/statements.py` |
| `TransactionController.java` | `app/routers/transactions.py` |
| `FinanceWebApplication.java` | `app/main.py` |
| `application.yml` | `app/config.py` |
| React `App.tsx` | `lib/screens/home_screen.dart` |
| React `StatementUpload.tsx` | `lib/widgets/statement_upload_widget.dart` |
| React `TransactionList.tsx` | `lib/widgets/transaction_list_widget.dart` |
| `docker-compose.yml` | `docker-compose.yml` |
| `Dockerfile` (Java) | `backend/Dockerfile` |
| `frontend/Dockerfile` (React) | `frontend/Dockerfile` |
