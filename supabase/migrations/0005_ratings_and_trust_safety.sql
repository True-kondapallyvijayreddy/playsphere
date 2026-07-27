-- Migration 0005: Ratings, Achievements, Guardian Links & Scouting Invites
CREATE TABLE IF NOT EXISTS rating_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_profile_id UUID NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    sport_id UUID NOT NULL REFERENCES sports(id),
    elo_rating INT NOT NULL DEFAULT 1200,
    matches_played INT NOT NULL DEFAULT 0,
    provisional BOOLEAN GENERATED ALWAYS AS (matches_played < 10) STORED,
    UNIQUE (player_profile_id, sport_id)
);

CREATE TABLE IF NOT EXISTS rating_history_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rating_record_id UUID NOT NULL REFERENCES rating_records(id) ON DELETE CASCADE,
    fixture_id UUID REFERENCES fixtures(id),
    old_rating INT NOT NULL,
    new_rating INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_profile_id UUID NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    badge_code TEXT NOT NULL,
    awarded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guardian_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    minor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    guardian_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (minor_user_id, guardian_user_id)
);

-- Trigger: Guardian must be an adult
CREATE OR REPLACE FUNCTION verify_guardian_adult()
RETURNS TRIGGER AS $$
DECLARE
    guardian_is_minor BOOLEAN;
BEGIN
    SELECT is_minor INTO guardian_is_minor FROM users WHERE id = NEW.guardian_user_id;
    IF guardian_is_minor THEN
        RAISE EXCEPTION 'Guardian must be an adult (above 18 years)';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER check_guardian_adult
    BEFORE INSERT OR UPDATE ON guardian_links
    FOR EACH ROW EXECUTE FUNCTION verify_guardian_adult();
