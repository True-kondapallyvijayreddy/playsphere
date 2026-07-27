# 42 Reporting and Exports Specification

## Purpose
The Reporting and Exports module provides automated generation of tournament certificates, PDF standings summaries, CSV member rosters, and financial export reports.

## Export Capabilities

### 1. Automated PDF Certificate Generation
- **Certificate Types:** Winner, Runner-Up, Certificate of Participation, Best Player Award.
- **Template Engine:** HTML/Canvas template styled with organization logo, tournament name, signature, and QR code.
- **QR Verification:** Each certificate includes a scanned link `https://playsphere.org/verify/cert/{certId}` confirming authenticity.

### 2. Standings & Roster CSV/Excel Exports
- **Leaderboard Export:** Export tournament standings (Rank, Team, Played, Won, Lost, Tied, Points, Net Run Rate / Goal Diff) to `.csv` or `.xlsx`.
- **Registration Roster Export:** Export participant lists with contact overrides and check-in status for venue marshals.

### 3. Financial & Monetization Reports
- **Revenue Summary:** Breakdown of registration fees collected, coupon discounts applied, and payout reports per season.

## API Endpoints
- `GET /api/v1/seasons/{seasonId}/export/standings?format=pdf|csv`
- `GET /api/v1/registrations/{regId}/certificate`\n