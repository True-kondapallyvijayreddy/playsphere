# 39 CI/CD Pipeline Specification

## Purpose
The Continuous Integration and Continuous Deployment (CI/CD) pipeline automates linting, testing, building, and deploying PlaySphere across Web, iOS, and Android platforms.

## CI/CD Workflow Stack
- **Platform:** GitHub Actions
- **Triggers:** Push to `main`, Pull Requests to `main` or `develop`.

## Pipeline Jobs

### Job 1: Static Analysis & Testing (`lint_and_test`)
- Setup Flutter SDK environment.
- Run `flutter pub get`.
- Run `flutter analyze` (fail on any error).
- Run `flutter test --coverage`.
- Upload coverage reports.

### Job 2: Web Build & Deployment (`deploy_web`)
- Depends on `lint_and_test`.
- Run `flutter build web --release --base-href "/"`.
- Deploy `/build/web` directory to AWS S3 / Cloudflare Pages.
- Purge CDN cache.

### Job 3: Android Build (`build_android`)
- Depends on `lint_and_test`.
- Setup Java 17 JDK & Android SDK.
- Run `flutter build appbundle --release`.
- Upload AAB artifact to Google Play Console Internal Track.

### Job 4: iOS Build (`build_ios`)
- Runs on macOS runner.
- Setup CocoaPods & Apple Developer Certificates.
- Run `flutter build ipa --release`.
- Upload IPA to TestFlight via Fastlane.

## GitHub Actions Workflow YAML Template
Located at `.github/workflows/main.yml` in the repository root.\n