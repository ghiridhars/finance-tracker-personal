"""
Application configuration using pydantic-settings.
Replaces Spring Boot's application.yml.
"""
import logging
from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import model_validator

logger = logging.getLogger(__name__)

_JWT_DEFAULT_SECRET = "CHANGE-ME-set-JWT_SECRET-env-var"


class Settings(BaseSettings):
    # Application
    app_name: str = "Finance Tracker v2"
    debug: bool = False

    # Server
    host: str = "0.0.0.0"
    port: int = 8080

    # Database - SQLite (replaces H2)
    database_url: str = "sqlite:///./data/finance_tracker.db"

    # File upload
    max_upload_size_mb: int = 10

    # CORS - FIX: explicit CORS config (was missing in Java version)
    # In development, allow all localhost ports for Flutter Web dev server
    cors_origins: list[str] = [
        "http://localhost:5173",   # Vite dev
        "http://localhost:8080",   # Same-origin
        "http://localhost:3000",   # Flutter --web-port 3000
        "http://localhost:8081",   # Alternative
        "http://localhost:49430",  # Random Flutter debug port
        "http://127.0.0.1:5173",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:3000",
    ]

    # Data directory
    data_dir: str = "./data"

    # JWT Authentication
    jwt_secret: str = _JWT_DEFAULT_SECRET  # Set via JWT_SECRET env var
    jwt_algorithm: str = "HS256"
    jwt_expiry_minutes: int = 1440  # 24 hours

    # LLM parser (primary when enabled)
    llm_provider: str = "ollama"  # "gemini" | "ollama" | "none"
    gemini_api_key: str = ""  # Set via GEMINI_API_KEY env var
    gemini_model: str = "gemini-2.0-flash"
    ollama_model: str = "lfm2-extract"
    ollama_host: str = "http://localhost:11434"

    # Google Drive sync
    gdrive_enabled: bool = False
    gdrive_credentials_file: str = ""  # Path to service account JSON key file
    gdrive_folder_id: str = ""  # Google Drive folder ID to watch
    gdrive_poll_interval_minutes: int = 60  # Auto-sync interval (0 = disabled)

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

    @model_validator(mode="after")
    def _warn_default_jwt_secret(self):
        if self.jwt_secret == _JWT_DEFAULT_SECRET:
            logger.warning(
                "⚠️  JWT_SECRET is using the default value. "
                "Set the JWT_SECRET environment variable before deploying."
            )
        return self

    @property
    def max_upload_size_bytes(self) -> int:
        return self.max_upload_size_mb * 1024 * 1024


settings = Settings()

# Ensure data directory exists
Path(settings.data_dir).mkdir(parents=True, exist_ok=True)
