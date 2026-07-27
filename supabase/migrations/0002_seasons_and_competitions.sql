-- Migration 0002: Sports Catalog, Seasons, Competitions & Registrations
CREATE TABLE IF NOT EXISTS sports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS leagues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sport_id UUID NOT NULL REFERENCES sports(id)
);

CREATE TABLE IF NOT EXISTS seasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    league_id UUID REFERENCES leagues(id),
    name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'active', 'completed', 'archived'))
);

CREATE TABLE IF NOT EXISTS points_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    win_points INT NOT NULL DEFAULT 3,
    draw_points INT NOT NULL DEFAULT 1,
    loss_points INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sport_competitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    season_id UUID NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
    sport_id UUID NOT NULL REFERENCES sports(id),
    title TEXT NOT NULL,
    entrant_kind TEXT NOT NULL CHECK (entrant_kind IN ('individual', 'team')),
    format TEXT NOT NULL CHECK (format IN ('round_robin', 'knockout', 'swiss', 'league_table')),
    points_config_id UUID REFERENCES points_configs(id),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'locked', 'in_progress', 'completed'))
);

CREATE TABLE IF NOT EXISTS registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_competition_id UUID NOT NULL REFERENCES sport_competitions(id) ON DELETE CASCADE,
    player_profile_id UUID NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'waitlisted', 'withdrawn', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique index ensuring max 1 active registration per player per competition
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_registrations
    ON registrations (sport_competition_id, player_profile_id)
    WHERE status IN ('pending', 'confirmed', 'waitlisted');
