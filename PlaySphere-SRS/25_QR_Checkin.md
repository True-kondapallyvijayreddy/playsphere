# 25. QR Code Check-in & Attendance

## 1. Overview
The QR Check-in System digitizes event entry, player verification, and attendance tracking. It removes the need for manual paper rosters, expedites venue entry, and acts as a verifiable digital ID for participants.

## 2. Core Features
- **Dynamic Digital ID**: Every verified participant receives a Digital ID card containing a secure, signed QR code.
- **Event-Specific QR**: For specific tournaments or seasons, a registration-specific QR code is generated.
- **Scanner Portal**: A dedicated interface (in the unified Flutter app) for Admins, Referees, and Judges to scan QRs.
- **Attendance Tracking**: Real-time logging of who is at the venue.

## 3. Scanning & Verification Workflow
1. **QR Generation**: Upon registration, backend generates a JWT-like payload or signed string containing `userId`, `registrationId`, and `expiry`.
2. **Display**: User opens the PlaySphere app > "My ID" to display the QR. Works offline if cached.
3. **Scanning**: Official opens Admin Portal > "Scan Pass". Uses device camera via `mobile_scanner` Flutter package.
4. **Validation**: App decodes QR, verifies cryptographic signature, and checks the backend (or local cache) for active status.
5. **Check-in**: Status is marked as `CHECKED_IN` for the specific `MatchEvent` or `Stage`.

## 4. Reporting & Analytics
- **Live Roster**: Organizers see real-time stats (e.g., "45/50 players arrived").
- **Absentee Management**: Auto-flag players who haven't checked in 15 minutes before fixture start; prompt for forfeit or substitute.
- **Export**: Download PDF/CSV of daily attendance.

## 5. Trust & Safety Integration
- When a minor's QR is scanned, the scanner UI distinctly displays the linked Guardian's contact info for emergency purposes.
- Verification Tiers (Casual vs. Sanctioned): For sanctioned state events, scanning the QR also pulls up the user's uploaded Government ID thumbnail for visual cross-verification by the official.

## 6. Data Model
- **AttendanceLogEntity**:
  - `id`: String
  - `eventId`: String
  - `userId`: String
  - `scannedByAdminId`: String
  - `timestamp`: Timestamp
  - `status`: Enum (CHECKED_IN, CHECKED_OUT, DENIED)
