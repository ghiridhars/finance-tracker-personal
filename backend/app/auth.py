"""
JWT Authentication module for the Finance Tracker API.

Provides:
  - Password hashing (bcrypt via passlib)
  - JWT token creation & validation
  - FastAPI dependency for protected routes
  - Login/register endpoints via auth_router

Single-user design: credentials stored in a local JSON file (not DB)
so auth works independently of the financial data layer.
"""
import json
import logging
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel

from app.config import settings

logger = logging.getLogger(__name__)

# ── Password hashing ────────────────────────────────────────
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── OAuth2 scheme (extracts Bearer token from Authorization header) ──
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

# ── User credentials file ───────────────────────────────────
_CREDENTIALS_FILE = Path(settings.data_dir) / ".credentials.json"


# ── Schemas ──────────────────────────────────────────────────
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class RegisterRequest(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    username: str


# ── Credential storage helpers ───────────────────────────────
def _load_credentials() -> Optional[dict]:
    """Load stored credentials from disk."""
    if not _CREDENTIALS_FILE.exists():
        return None
    try:
        data = json.loads(_CREDENTIALS_FILE.read_text(encoding="utf-8"))
        return data
    except (json.JSONDecodeError, KeyError):
        return None


def _save_credentials(username: str, hashed_password: str) -> None:
    """Persist credentials to disk with restricted permissions."""
    _CREDENTIALS_FILE.parent.mkdir(parents=True, exist_ok=True)
    data = {"username": username, "hashed_password": hashed_password}
    _CREDENTIALS_FILE.write_text(
        json.dumps(data), encoding="utf-8"
    )
    try:
        import os
        os.chmod(_CREDENTIALS_FILE, 0o600)
    except OSError:
        logger.warning("Could not restrict credentials file permissions")


def _is_registered() -> bool:
    """Check if a user has already registered."""
    return _load_credentials() is not None


# ── Core auth functions ──────────────────────────────────────
def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(subject: str) -> tuple[str, int]:
    """Create a JWT token. Returns (token, expires_in_seconds)."""
    expires_seconds = settings.jwt_expiry_minutes * 60
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expiry_minutes)
    payload = {
        "sub": subject,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_seconds


def decode_access_token(token: str) -> Optional[str]:
    """Decode and validate a JWT. Returns the username or None."""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        return payload.get("sub")
    except JWTError:
        return None


# ── FastAPI dependency ───────────────────────────────────────
async def get_current_user(token: str = Depends(oauth2_scheme)) -> str:
    """
    Dependency that validates the JWT and returns the username.
    Use as: Depends(get_current_user) on protected routes.
    """
    username = decode_access_token(token)
    if username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # Verify user still exists in credentials
    creds = _load_credentials()
    if creds is None or creds.get("username") != username:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return username


# ── Simple login rate limiter ────────────────────────────────
_LOGIN_ATTEMPTS: dict[str, list[float]] = defaultdict(list)
_MAX_ATTEMPTS = 5       # per window
_WINDOW_SECONDS = 300   # 5 minutes


def _check_rate_limit(client_ip: str) -> None:
    """Raise 429 if too many login attempts from this IP."""
    now = time.time()
    attempts = _LOGIN_ATTEMPTS[client_ip]
    # Prune old entries
    _LOGIN_ATTEMPTS[client_ip] = [t for t in attempts if now - t < _WINDOW_SECONDS]
    if len(_LOGIN_ATTEMPTS[client_ip]) >= _MAX_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Try again later.",
        )
    _LOGIN_ATTEMPTS[client_ip].append(now)


# ── Auth router ──────────────────────────────────────────────
auth_router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@auth_router.post("/register", response_model=Token)
def register(body: RegisterRequest):
    """
    Register the single user. Can only be called once.
    After registration, this endpoint returns 400.
    """
    if _is_registered():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User already registered. Only one user is allowed.",
        )

    if len(body.password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 8 characters.",
        )

    hashed = hash_password(body.password)
    _save_credentials(body.username, hashed)
    logger.info(f"User '{body.username}' registered successfully")

    token, expires_in = create_access_token(body.username)
    return Token(access_token=token, expires_in=expires_in)


@auth_router.post("/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), request: Request = None):
    """
    Authenticate and get a JWT token.
    Uses OAuth2 password flow (username + password form).
    """
    # Rate limit by client IP
    client_ip = request.client.host if request and request.client else "unknown"
    _check_rate_limit(client_ip)
    creds = _load_credentials()
    if creds is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No user registered. Please register first.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if (
        form_data.username != creds["username"]
        or not verify_password(form_data.password, creds["hashed_password"])
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token, expires_in = create_access_token(form_data.username)
    return Token(access_token=token, expires_in=expires_in)


@auth_router.get("/me", response_model=UserOut)
def get_me(current_user: str = Depends(get_current_user)):
    """Return the currently authenticated user."""
    return UserOut(username=current_user)


@auth_router.get("/status")
def auth_status():
    """Check if a user has been registered (public endpoint)."""
    return {"registered": _is_registered()}
