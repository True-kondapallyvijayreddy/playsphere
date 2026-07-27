-- Migration 0004: Stages, Entrants, Fixtures, Match Events & Standings
CREATE TABLE IF NOT EXISTS stages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_competition_id UUID NOT NULL REFERENCES sport_competitions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sequence_no INT NOT NULL
);

CREATE TABLE IF NOT EXISTS entrants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_competition_id UUID NOT NULL REFERENCES sport_competitions(id) ON DELETE CASCADE,
    player_profile_id UUID REFERENCES player_profiles(id),
    team_id UUID REFERENCES teams(id),
    CONSTRAINT single_entrant_type CHECK (
        (player_profile_id IS NOT NULL AND team_id IS NULL) OR
        (player_profile_id IS NULL AND team_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS fixtures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stage_id UUID NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    entrant_a_id UUID NOT NULL REFERENCES entrants(id),
    entrant_b_id UUID NOT NULL REFERENCES entrants(id),
    winner_entrant_id UUID REFERENCES entrants(id),
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'live', 'under_dispute', 'finalized')),
    scheduled_at TIMESTAMPTZ,
    venue_name TEXT,
    CONSTRAINT distinct_entrants CHECK (entrant_a_id <> entrant_b_id)
);

CREATE TABLE IF NOT EXISTS match_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fixture_id UUID NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
    sequence_no INT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (fixture_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS standings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sport_competition_id UUID NOT NULL REFERENCES sport_competitions(id) ON DELETE CASCADE,
    entrant_id UUID NOT NULL REFERENCES entrants(id) ON DELETE CASCADE,
    played INT DEFAULT 0,
    won INT DEFAULT 0,
    drawn INT DEFAULT 0,
    lost INT DEFAULT 0,
    points INT DEFAULT 0,
    point_difference INT DEFAULT 0,
    UNIQUE (sport_competition_id, entrant_id)
);
