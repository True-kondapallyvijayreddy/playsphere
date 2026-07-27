# 33 Database Schema Specification

## Purpose
The PlaySphere database schema is built on PostgreSQL (hosted via Supabase) utilizing multi-tenant Row Level Security (RLS), JSONB feature flags, and foreign key relationships across 10 core domain phases.

## Schema Overview

### 1. Identity & Auth (`public` schema)
- `users` (id UUID PRIMARY KEY, full_name TEXT, email TEXT UNIQUE, phone TEXT, date_of_birth DATE, auth_provider TEXT, account_status TEXT, created_at TIMESTAMPTZ)
- `organizations` (id UUID PRIMARY KEY, name TEXT, slug TEXT UNIQUE, org_type TEXT, parent_org_id UUID REFERENCES organizations(id), feature_flags JSONB, created_at TIMESTAMPTZ)
- `organization_memberships` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), user_id UUID REFERENCES users(id), role TEXT, status TEXT, membership_tag TEXT, UNIQUE(org_id, user_id))
- `player_profiles` (id UUID PRIMARY KEY, user_id UUID REFERENCES users(id) UNIQUE, display_name TEXT, primary_sport_ids TEXT[], visibility_default TEXT, career_page_slug TEXT UNIQUE)

### 2. Seasons & Competitions
- `seasons` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), name TEXT, status TEXT, start_date DATE, end_date DATE)
- `sport_competitions` (id UUID PRIMARY KEY, season_id UUID REFERENCES seasons(id), sport_id TEXT, name TEXT, entrant_type TEXT, format TEXT, status TEXT)

### 3. Teams & Fixtures
- `teams` (id UUID PRIMARY KEY, org_id UUID REFERENCES organizations(id), team_kind TEXT, name TEXT, is_active BOOLEAN)
- `stages` (id UUID PRIMARY KEY, sport_competition_id UUID REFERENCES sport_competitions(id), name TEXT, stage_order INT, stage_format TEXT, status TEXT)
- `fixtures` (id UUID PRIMARY KEY, stage_id UUID REFERENCES stages(id), entrant_a_id UUID, entrant_b_id UUID, status TEXT, result_entrant_id UUID, is_draw BOOLEAN, verification_tier TEXT)
- `match_events` (id UUID PRIMARY KEY, fixture_id UUID REFERENCES fixtures(id), event_type TEXT, payload JSONB, sequence_no INT, entered_by_user_id UUID, created_at TIMESTAMPTZ)

### 4. Ratings & Achievements
- `rating_records` (id UUID PRIMARY KEY, player_profile_id UUID REFERENCES player_profiles(id), sport_id TEXT, current_rating FLOAT, rating_status TEXT, matches_played INT, UNIQUE(player_profile_id, sport_id))
- `rating_history_entries` (id UUID PRIMARY KEY, rating_record_id UUID REFERENCES rating_records(id), rating_before FLOAT, rating_after FLOAT, expected_score FLOAT, actual_score FLOAT, k_factor_used FLOAT)
- `achievements` (id UUID PRIMARY KEY, player_profile_id UUID REFERENCES player_profiles(id), sport_id TEXT, description TEXT, verification_tier TEXT)

## Indexes & Performance
- `CREATE INDEX idx_match_events_fixture_seq ON match_events(fixture_id, sequence_no);`
- `CREATE INDEX idx_fixtures_stage ON fixtures(stage_id);`
- `CREATE INDEX idx_org_memberships_user ON organization_memberships(user_id);`

## Row Level Security (RLS)
- Organization members can read data belonging to their `org_id`.
- Admins/Owners have write permissions within their `org_id`.\n