# 38 Deployment Architecture Specification

## Purpose
This document details the production cloud deployment architecture, infrastructure topology, containerization, and scaling strategies for PlaySphere.

## Infrastructure Topology

```
                   +------------------------+
                   |  Cloudflare CDN / DNS  |
                   +-----------+------------+
                               |
               +---------------+---------------+
               |                               |
       +-------v-------+               +-------v-------+
       | Flutter Web   |               | REST API / WS |
       | Static (S3)   |               | Kubernetes K8s|
       +---------------+               +-------+-------+
                                               |
                                       +-------v-------+
                                       | Supabase DB   |
                                       | PostgreSQL    |
                                       +---------------+
```

## Hosting & CDN Strategy
- **Flutter Web Client:** Static web build (`flutter build web --release`) hosted on AWS S3 / Cloudflare Pages behind global Cloudflare CDN with SSL/TLS edge termination.
- **Mobile Clients:** Distributed via Apple App Store (iOS IPA) and Google Play Store (Android APK/AAB).
- **Backend API & WebSockets:** Containerized Node.js/Go services deployed on Kubernetes (EKS/GKE) with Auto-scaling (HPA) based on CPU and concurrent WebSocket connection metrics.
- **Database Layer:** Managed Supabase / PostgreSQL instance with Primary-Replica read scaling and automated daily WAL backups.

## Containerization (Docker)
```dockerfile
# Multi-stage build for Flutter Web
FROM plugfox/flutter:3.22.0 AS build
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```\n