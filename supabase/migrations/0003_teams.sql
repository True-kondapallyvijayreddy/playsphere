-- Migration 0003: Teams, Rosters & Auction Lots
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    league_id UUID REFERENCES leagues(id),
    name TEXT NOT NULL,
    team_kind TEXT NOT NULL CHECK (team_kind IN ('ad_hoc', 'franchise')),
    owner_user_id UUID REFERENCES users(id),
    CONSTRAINT franchise_owner_check CHECK (
        (team_kind = 'franchise' AND league_id IS NOT NULL AND owner_user_id IS NOT NULL) OR
        (team_kind = 'ad_hoc')
    )
);

CREATE TABLE IF NOT EXISTS franchise_roster_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    player_profile_id UUID NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    salary_paise BIGINT NOT NULL DEFAULT 0,
    acquired_via TEXT CHECK (acquired_via IN ('draft', 'auction', 'trade', 'free_agency')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auction_lots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id UUID NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
    player_profile_id UUID NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    winning_team_id UUID REFERENCES teams(id),
    winning_bid_paise BIGINT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'sold', 'unsold'))
);

-- Trigger: Sold Lot automatically inserts Franchise Roster Entry
CREATE OR REPLACE FUNCTION process_sold_auction_lot()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'sold' AND NEW.winning_team_id IS NOT NULL THEN
        INSERT INTO franchise_roster_entries (team_id, player_profile_id, salary_paise, acquired_via)
        VALUES (NEW.winning_team_id, NEW.player_profile_id, COALESCE(NEW.winning_bid_paise, 0), 'auction');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER on_lot_sold
    AFTER UPDATE OF status ON auction_lots
    FOR EACH ROW EXECUTE FUNCTION process_sold_auction_lot();
