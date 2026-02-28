"""
FastAPI application entry point.
Replaces: FinancialTrackerApplication.java (Spring Boot @SpringBootApplication)

FIX: Adds proper CORS middleware (missing in Java version).
FIX: Adds global exception handlers (replaces GlobalExceptionHandler.java).
FIX: Configures consistent 10MB upload limit via config.
"""
import logging
import sys
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.database import create_tables
from app.routers import (
    health_router,
    transactions_router,
    upload_router,
    categories_router,
    unified_transactions_router,
    tags_router,
    analytics_router,
    accounts_router,
    budgets_router,
    goals_router,
    reminders_router,
    export_router,
)

# ──────────────────────────────────────────────────────────────
# Logging setup (replaces System.out.println scattered in Java code)
# ──────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────────
# Application lifecycle
# ──────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Replaces: Spring Boot auto-configuration lifecycle.
    Creates database tables on startup.
    """
    logger.info("Starting Finance Tracker v2 (Python + FastAPI)")
    create_tables()
    logger.info(f"Database initialized: {settings.database_url}")

    # Seed default categories
    from app.database import SessionLocal
    from app.services.category_service import CategoryService
    seed_db = SessionLocal()
    try:
        CategoryService.seed_defaults(seed_db)
    finally:
        seed_db.close()

    logger.info(f"Finance Tracker started at http://localhost:{settings.port}")
    yield
    logger.info("Finance Tracker shutting down")


# ──────────────────────────────────────────────────────────────
# FastAPI app
# ──────────────────────────────────────────────────────────────
app = FastAPI(
    title=settings.app_name,
    description="Personal Finance Management API — migrated from Spring Boot to FastAPI",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",           # Swagger UI (replaces springdoc-openapi)
    redoc_url="/redoc",         # ReDoc (bonus — not available in Java version)
    openapi_url="/v3/api-docs", # OpenAPI spec URL (same path as springdoc)
)


# ──────────────────────────────────────────────────────────────
# CORS middleware — FIX: was missing in Java version
# Allow all origins in development mode (no auth = no risk)
# ──────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ──────────────────────────────────────────────────────────────
# Global exception handlers (replaces GlobalExceptionHandler.java)
# ──────────────────────────────────────────────────────────────
@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    """Replaces: handleBadRequest in GlobalExceptionHandler"""
    return JSONResponse(
        status_code=400,
        content={
            "timestamp": datetime.now().isoformat(),
            "status": 400,
            "error": "Bad Request",
            "message": str(exc),
        },
    )


@app.exception_handler(FileNotFoundError)
async def file_not_found_handler(request: Request, exc: FileNotFoundError):
    """Replaces: handleNotFound in GlobalExceptionHandler"""
    return JSONResponse(
        status_code=404,
        content={
            "timestamp": datetime.now().isoformat(),
            "status": 404,
            "error": "Not Found",
            "message": str(exc),
        },
    )


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception):
    """Replaces: handleOther in GlobalExceptionHandler"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "timestamp": datetime.now().isoformat(),
            "status": 500,
            "error": "Internal Server Error",
            "message": str(exc),
        },
    )


# ──────────────────────────────────────────────────────────────
# Register routers (replaces @RestController component scanning)
# ──────────────────────────────────────────────────────────────
app.include_router(health_router)
app.include_router(transactions_router)
app.include_router(upload_router)
app.include_router(categories_router)
app.include_router(unified_transactions_router)
app.include_router(tags_router)
app.include_router(analytics_router)
app.include_router(accounts_router)
app.include_router(budgets_router)
app.include_router(goals_router)
app.include_router(reminders_router)
app.include_router(export_router)


# ──────────────────────────────────────────────────────────────
# Root endpoint (replaces HomeController.java Thymeleaf redirect)
# ──────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "app": settings.app_name,
        "version": "2.0.0",
        "docs": "/docs",
        "health": "/health",
    }
