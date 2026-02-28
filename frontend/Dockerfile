# ── Frontend Dockerfile ─────────────────────────────────────────
# Multi-stage: Flutter build → nginx serve
# Replaces: React Vite build + nginx
#
# Build:  docker build -t finance-tracker-frontend -f frontend/Dockerfile frontend/
# Run:    docker run -p 3000:80 finance-tracker-frontend
# ── Stage 1: Build Flutter Web ──
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

RUN flutter pub get
RUN flutter build web --release

# ── Stage 2: Serve with nginx ──
FROM nginx:alpine

# Copy built web app
COPY --from=build /app/build/web /usr/share/nginx/html

# Custom nginx config for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
