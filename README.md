# Finance Tracker v2

A personal finance management app to upload bank statements, auto-categorize transactions, and visualize spending. Built with Python/FastAPI + Flutter.

## Features

- **Authentication** — Single-user JWT-based login with registration, bcrypt password hashing, and credential persistence
- Multi-bank PDF & CSV statement upload (HDFC, ICICI, SBI, Axis, Kotak, Yes Bank, Bank of Baroda, Federal Bank + any other bank)
- Password-protected PDF support
- Auto-categorization with 15 default categories, keyword matching, and MCC code mapping
- Customizable dashboard with spending trends, category breakdown, income vs expense charts
- 12-column responsive grid layout with per-tile resize, reorder, and visibility controls
- Full-page spending calendar heatmap with per-bank color-coded breakdown and editable transaction categories
- **Account-centric transactions** — Click any account to view its filtered transactions inline with editable categories
- **Review Pane** — Dedicated screen to batch review and categorize doubtful transactions flagged during statement parsing, accessible via a notification badge
- **Investment Portfolio** — Dedicated investments screen with dynamic Asset Classes (custom name, color, icon), a Smart Mapping rule engine, and an "Inbox Zero" queue for unclassified investment transactions
- **Glassmorphic UI** — Modern, translucent design language tailored for desktop environments
- **Transfer detection** — Auto-detect and manually link inter-account transfers and CC bill payments
- **UPI ID management** — Map UPI handles to accounts/categories for auto-categorization and transfer flagging
- Monthly budgets per category with progress tracking
- Savings goals with contribution tracking
- Bill reminders with auto-detection from credit card dues
- Recurring transaction detection
- **Google Drive Sync** — OAuth2-based import from personal Google Drive with folder browsing, bank/type mapping, and background processing
- **Local Directory Sync** — Scan and import statements from a local folder with background processing and job tracking
- **Database Manager** — Admin panel for browsing and editing all database tables with schema introspection
- CSV/JSON export
- Dark/Light theme, responsive layout (desktop sidebar, mobile bottom nav)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.12+, FastAPI 0.115, SQLAlchemy 2.0, Pydantic 2.9 |
| Frontend | Flutter 3.x, Material Design 3, Riverpod 3.2, GoRouter |
| Database | SQLite (WAL mode, foreign keys) |
| PDF Parsing | pdfplumber + pymupdf + Gemini/Ollama LLM fallback |
| Deployment | Docker Compose (nginx + uvicorn) |

## Quick Start

### 1. Backend

```bash
cd backend
python -m venv .venv

# Windows
.\.venv\Scripts\Activate.ps1
# Linux/Mac
source .venv/bin/activate

pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
```

- Health check: http://localhost:8080/health
- Swagger UI: http://localhost:8080/docs
- ReDoc: http://localhost:8080/redoc

### 2. Frontend

```bash
cd frontend
flutter pub get

# Browser
flutter run -d chrome --web-port 3000

# Windows desktop
flutter run -d windows
```

### 3. Docker (both services)

```bash
docker-compose up --build
# Frontend → http://localhost:3000
# Backend  → http://localhost:8080
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite:///./data/finance_tracker.db` | SQLAlchemy connection string |
| `CORS_ORIGINS` | `http://localhost:3000,...` | Allowed origins (comma-separated) |
| `JWT_SECRET` | `CHANGE-ME-...` | Secret key for JWT token signing (change in production!) |
| `JWT_EXPIRY_MINUTES` | `1440` | JWT token lifetime (default: 24 hours) |
| `GEMINI_API_KEY` | — | Google Gemini API key for LLM parser |
| `LLM_PROVIDER` | `ollama` | LLM provider: `gemini`, `ollama`, or `none` |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_MODEL` | `lfm2-extract` | Ollama model name |
| `GDRIVE_OAUTH_SECRETS_FILE` | `credentials_google.json` | Path to Google OAuth client secrets JSON |
| `LOCAL_SYNC_PATH` | — | Local folder path for directory sync |
| `LOCAL_SYNC_MAX_FILES` | `500` | Max files returned per scan |
| `LOCAL_SYNC_ALLOWED_ROOTS` | — | Comma-separated allowed root dirs (empty = home + data_dir) |

## Project Structure

```
finance-tracker-v2/
├── backend/
│   ├── app/
│   │   ├── main.py          # FastAPI app entry point
│   │   ├── config.py         # Settings (env-based)
│   │   ├── database.py       # SQLAlchemy engine + session
│   │   ├── auth.py           # JWT authentication (register/login/token)
│   │   ├── models/           # 17+ SQLAlchemy ORM models (6 enums)
│   │   ├── schemas/          # Pydantic request/response DTOs
│   │   ├── parsers/          # PDF/CSV parsers + LLM fallback
│   │   ├── services/         # Business logic layer (16 services)
│   │   ├── routers/          # 20+ API route modules (~130+ endpoints)
│   │   └── utils/            # Shared utilities (file_utils.py)
│   └── requirements.txt
├── frontend/
│   ├── lib/
│   │   ├── main.dart         # App entry (MaterialApp.router)
│   │   ├── router.dart       # GoRouter config (6 nav destinations)
│   │   ├── theme.dart        # Light/dark theme
│   │   ├── models/           # Dart data models (incl. AssetClass, InvestmentRule)
│   │   ├── providers/        # Riverpod state management (16+ providers)
│   │   ├── screens/          # App shell, login, calendar, investments, import, settings, database manager, review pane
│   │   ├── services/         # API client + auth service + modular API layer
│   │   └── widgets/          # Dashboard, accounts, UPI, charts/
│   └── pubspec.yaml
├── docker-compose.yml
└── docs/
    ├── ARCHITECTURE.md       # Mermaid architecture diagrams
    ├── FLOW.md               # User flows & API reference
    ├── OVERVIEW.md           # Technical specification & schema
    ├── ISSUES.md             # Known issues & improvement areas
    └── PARSING.md            # PDF parsing strategy reference
```

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Mermaid diagrams: system architecture, data flow, ER diagram, deployment
- [FLOW.md](docs/FLOW.md) — All user flows with API endpoints and details
- [OVERVIEW.md](docs/OVERVIEW.md) — Technical spec, database schema, architecture, and future enhancements
- [ISSUES.md](docs/ISSUES.md) — Known issues, technical debt, and improvement areas
- [PARSING.md](docs/PARSING.md) — PDF parsing strategy reference and bank compatibility
