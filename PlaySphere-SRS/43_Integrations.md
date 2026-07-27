# 43 Integrations Specification

## Purpose
This document specifies external third-party integrations connecting PlaySphere to payment gateways, messaging networks, media storage, and authentication providers.

## Key Third-Party Integrations

### 1. Payment Gateways (Razorpay & Stripe)
- **Use Case:** Event registration fees, season passes, franchise auction deposits.
- **Currency Support:** Primary INR (Paise representation `int`), secondary USD/EUR.
- **Webhook Handlers:** Asynchronous payment confirmation (`payment.captured`) triggering automatic registration status update (`pending -> confirmed`).

### 2. Push Notifications & SMS (Firebase FCM & Twilio)
- **Use Case:** Push notifications for live score alerts, match schedule changes, OTP delivery.
- **Fallback:** SMS/WhatsApp OTP fallback when push notification delivery fails.

### 3. Cloud Media Storage (AWS S3 & Cloudflare R2)
- **Use Case:** Image uploads (organization logos, user avatars, match gallery photos) and PDF certificate hosting.
- **Optimization:** Pre-signed upload URLs and automatic WebP image compression.

### 4. WhatsApp Business API
- **Use Case:** Automated match schedule reminders and digital tournament pass delivery directly to participant WhatsApp numbers.\n