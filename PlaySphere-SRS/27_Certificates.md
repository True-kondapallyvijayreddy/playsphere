# 27. Certificate Generation

## 1. Overview
PlaySphere automates the creation, distribution, and verification of digital certificates. This removes massive administrative overhead for organizers and provides players with verifiable proof of their achievements for their career resumes.

## 2. Types of Certificates
- **Participation**: Auto-generated for anyone with `CHECKED_IN` status at a stage/event.
- **Winner / Runner-Up**: Generated based on finalized bracket/tournament results.
- **Special Awards**: (e.g., "Best Player", "Fair Play") Manually assigned by organizers.

## 3. Template Engine
- **Org Branding**: Organizers upload a background template (PDF or high-res Image) and configure text bounding boxes via the web admin portal.
- **Dynamic Injection**: The backend uses a library (like Puppeteer or a native PDF lib) to overlay dynamic text (User Name, Event Name, Date, Rank) onto the template.

## 4. Verifiability
- Every certificate embeds a unique QR code and a verification URL (e.g., `playsphere.io/verify/cert123`).
- Scanning the QR or visiting the link shows a public, read-only page confirming the authenticity, the issuing Organization, and the recipient.

## 5. Delivery & Storage
- Once a tournament ends, a batch process generates the PDFs.
- Users receive an Email and In-App Notification.
- The certificate is permanently pinned to the user's Portable Player Profile (Career Resume).

## 6. Data Model
- **CertificateEntity**:
  - `id`: String (UUID)
  - `userId`: String
  - `orgId`: String
  - `seasonId`: String
  - `type`: Enum (PARTICIPATION, WINNER, RUNNER_UP, MERIT)
  - `pdfUrl`: String (Cloud storage link)
  - `verificationHash`: String
  - `issuedAt`: Timestamp

## 7. Workflow for Admins
1. Admin opens "Certificate Settings" for a Season.
2. Selects Template.
3. Maps variables: `{{PLAYER_NAME}}`, `{{TEAM_NAME}}`, `{{AWARD}}`.
4. Previews with dummy data.
5. Clicks "Issue Certificates" post-tournament. System processes async.
