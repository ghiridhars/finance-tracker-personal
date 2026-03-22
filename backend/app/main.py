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

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.auth import auth_router
from app.config import settings
from app.database import create_tables, migrate_schema
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
    gdrive_router,
    transfers_router,
    upi_router,
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
    migrate_schema()
    logger.info(f"Database initialized: {settings.database_url}")

    # Seed default categories + upgrade keywords + MCC codes
    from app.database import SessionLocal
    from app.services.category_service import CategoryService
    seed_db = SessionLocal()
    try:
        CategoryService.seed_defaults(seed_db)
        added = CategoryService.upgrade_keywords(seed_db)
        if added:
            logger.info(f"Keyword upgrade: {added} new keywords added")
            
        mcc_added = CategoryService.seed_mcc_codes(seed_db)
        if mcc_added:
            logger.info(f"MCC seed: {mcc_added} new MCC codes added")
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
# CORS middleware — restricted to configured origins
# ──────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


# ──────────────────────────────────────────────────────────────
# Global exception handlers (replaces GlobalExceptionHandler.java)
# ──────────────────────────────────────────────────────────────
@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    """Handle validation / bad-request errors. Safe to echo back."""
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
    """Handle not-found errors with a generic message."""
    return JSONResponse(
        status_code=404,
        content={
            "timestamp": datetime.now().isoformat(),
            "status": 404,
            "error": "Not Found",
            "message": "The requested resource was not found.",
        },
    )


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception):
    """Handle unexpected errors. Never leak internal details to the client."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "timestamp": datetime.now().isoformat(),
            "status": 500,
            "error": "Internal Server Error",
            "message": "An unexpected error occurred. Please try again later.",
        },
    )


# ──────────────────────────────────────────────────────────────
# Register routers (replaces @RestController component scanning)
# ──────────────────────────────────────────────────────────────
# Public routes (no auth required)
app.include_router(auth_router)
app.include_router(health_router)

# Protected routes (require valid JWT)
from app.auth import get_current_user

for protected_router in [
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
    gdrive_router,
    transfers_router,
    upi_router,
]:
    # Inject auth dependency into every route of each protected router
    protected_router.dependencies.append(Depends(get_current_user))
    app.include_router(protected_router)


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
