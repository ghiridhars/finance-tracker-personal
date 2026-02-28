# ── Backend Dockerfile ──────────────────────────────────────────
# Python 3.12 slim image with FastAPI + uvicorn
# Replaces: Java Dockerfile (OpenJDK 17 + Gradle multi-stage build)
#
# Build:  docker build -t finance-tracker-backend -f backend/Dockerfile backend/
# Run:    docker run -p 8080:8080 -v finance-data:/app/data finance-tracker-backend
FROM python:3.12-slim

# System deps for pdfplumber (uses pdfminer.six, no native libs needed)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create data directory for SQLite
RUN mkdir -p /app/data

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run with uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
