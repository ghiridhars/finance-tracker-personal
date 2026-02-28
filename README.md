# Finance Tracker v2

A personal finance management app to upload bank statements, auto-categorize transactions, and visualize spending. Built with Python/FastAPI + Flutter.

## Features

- Multi-bank PDF & CSV statement upload (HDFC, ICICI, SBI, Axis, Kotak, Yes Bank + LLM fallback for any bank)
- Auto-categorization with 15 default categories and keyword matching
- Dashboard with spending trends, category breakdown, income vs expense charts
- Monthly budgets per category with progress tracking
- Savings goals with contribution tracking
- Bill reminders with auto-detection from credit card dues
- Recurring transaction detection
- CSV/JSON export
- Dark/Light theme, responsive layout (desktop sidebar, mobile bottom nav)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11+, FastAPI 0.115, SQLAlchemy 2.0, Pydantic 2.9 |
| Frontend | Flutter 3.x, Material Design 3, Riverpod 3.2, GoRouter |
| Database | SQLite (WAL mode, foreign keys) |
| PDF Parsing | pdfplumber + Gemini/Ollama LLM fallback |
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
| `DATABASE_URL` | `sqlite:///./data/financial-tracker.db` | SQLAlchemy connection string |
| `CORS_ORIGINS` | `http://localhost:3000,...` | Allowed origins (comma-separated) |
| `GEMINI_API_KEY` | — | Google Gemini API key for LLM parser |
| `LLM_PROVIDER` | `gemini` | LLM provider: `gemini`, `ollama`, or `none` |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |

## Project Structure

```
finance-tracker-v2/
├── backend/
│   ├── app/
│   │   ├── main.py          # FastAPI app entry point
│   │   ├── config.py         # Settings (env-based)
│   │   ├── database.py       # SQLAlchemy engine + session
│   │   ├── models/           # 12 SQLAlchemy ORM models
│   │   ├── schemas/          # Pydantic request/response DTOs
│   │   ├── parsers/          # PDF/CSV parsers + LLM fallback
│   │   ├── services/         # Business logic layer
│   │   └── routers/          # 15 API route modules (73 endpoints)
│   ├── alembic/              # Database migrations
│   └── requirements.txt
├── frontend/
│   ├── lib/
│   │   ├── main.dart         # App entry (MaterialApp.router)
│   │   ├── router.dart       # GoRouter config (8 routes)
│   │   ├── theme.dart        # Light/dark theme
│   │   ├── models/           # Dart data models
│   │   ├── providers/        # Riverpod state management
│   │   ├── screens/          # App shell, settings
│   │   ├── services/         # API client
│   │   └── widgets/          # Dashboard, upload, transactions, etc.
│   └── pubspec.yaml
├── docker-compose.yml
└── docs/
    ├── FLOW.md               # User flows & API reference
    └── OVERVIEW.md           # Technical specification & schema
```

## Documentation

- [FLOW.md](docs/FLOW.md) — All user flows with API endpoints and details
- [OVERVIEW.md](docs/OVERVIEW.md) — Technical spec, database schema, architecture, and future enhancements
