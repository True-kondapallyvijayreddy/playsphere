# 23. Notifications System

## 1. Overview
The PlaySphere Notifications System ensures that all participants, organizers, and guardians receive timely updates regarding platform events. It employs Firebase Cloud Messaging (FCM) for push notifications, an internal inbox for in-app notifications, and a transactional email service (e.g., SendGrid/AWS SES) for critical alerts.

## 2. Notification Channels
- **Push Notifications**: Delivered via FCM to iOS and Android devices. For urgent updates (live scores, match starts).
- **In-App Notifications**: Stored persistently for all users, accessed via the "bell" icon. Syncs across web and mobile.
- **Email Notifications**: Used for formal communications like receipts, registration confirmations, and certificates.

## 3. Key Triggers & Event Types
| Trigger Event | Audience | Channels | Description |
| --- | --- | --- | --- |
| **Match Scheduled/Changed** | Players, Guardians, Officials | Push, In-App | Notifies participants of match time, venue, or changes. |
| **Live Score Update** | Followers, Participants | Push | Sent at key milestones (e.g., halftime, full time, milestones). |
| **Registration Confirmed** | User, Guardian | Email, In-App | Confirmation of successful enrollment in a season/sport. |
| **Team Assignment** | Player | Push, In-App | Triggered when snake draft or franchise auction is completed. |
| **Achievement Earned** | Player | Push, In-App | When a player reaches a new ELO tier or wins a medal. |
| **Season Status Change** | All Org Members | Email, In-App | E.g., Season opens for registration, Season begins, Season ends. |

## 4. Notification Preferences
Users can control the types of notifications they receive per channel.
- Global toggles for Push, Email.
- Granular toggles by category (e.g., "Mute Live Scores", "Enable Registration Alerts").
- Quiet Hours: Define times when push notifications are suppressed (except for critical security alerts).

## 5. Architecture & Data Model
- Notifications are managed asynchronously via a message broker (e.g., Redis/RabbitMQ) to prevent blocking main API flows.
- **NotificationEntity**:
  - `id`: String (UUID)
  - `userId`: String (Foreign Key)
  - `title`: String
  - `body`: String
  - `type`: Enum (MATCH, REGISTRATION, SYSTEM, PROMO)
  - `isRead`: Boolean
  - `actionUrl`: String (Deep link for Flutter go_router)
  - `createdAt`: Timestamp

## 6. Trust & Safety (Guardian Links)
If a user is verified as a minor, notifications regarding schedules, locations, and direct team assignments are automatically CC'd to their verified Guardian via Email and Push.

## 7. Future Enhancements
- WhatsApp/SMS integration for rural or community-level orgs.
- Actionable push notifications (e.g., RSVP "Yes/No" directly from the lock screen).
