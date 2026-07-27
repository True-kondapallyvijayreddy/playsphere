# 28. Analytics & Dashboards

## 1. Overview
The Analytics module provides actionable insights across multiple dimensions of the PlaySphere ecosystem. It serves Org Admins with operational metrics and Players with personal performance tracking.

## 2. Organization Dashboard (Admin Portal)
Targeted at Directors, Admins, and Operations staff.
- **Registrations & Growth**: Trendlines showing daily sign-ups per season.
- **Financial Revenue**: Total revenue, average revenue per user (ARPU), pending payouts.
- **Attendance & Churn**: Drop-off rates (Registered vs. Checked-in).
- **Demographics**: Breakdown by age groups, gender, and geography (useful for state/national bodies).
- **Sport Popularity**: Heatmaps or pie charts showing which sports draw the most engagement within multi-sport seasons.

## 3. Player Analytics (Participant Portal)
Targeted at the individual athlete.
- **ELO Rating Trend**: A time-series graph plotting ELO rating changes across matches.
- **Win/Loss Ratio**: Global and sport-specific win rates.
- **Activity Heatmap**: GitHub-style contribution graph showing match frequency over the year.
- **Performance by Sport**: Spider/Radar charts comparing skill levels across different sports.

## 4. Season Analytics
Metrics tied to a specific `Season` entity.
- **Completion Rate**: Percentage of scheduled fixtures actually completed vs. forfeited.
- **Resource Utilization**: Court/Venue occupancy rates.
- **Engagement**: Total gallery media uploads, average crowd size (if tracked).

## 5. Technical Implementation
- **Data Aggregation**: Real-time stats are expensive. We use materialized views or scheduled background cron jobs (running nightly) to aggregate raw transaction/match data into `AnalyticsSnapshot` tables.
- **UI Components**: Flutter uses packages like `fl_chart` or `syncfusion_flutter_charts` for rendering interactive, responsive data visualizations.
- **Export**: Admins can export raw filtered datasets as CSV for external analysis.
