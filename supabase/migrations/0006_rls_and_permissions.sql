-- Migration 0006: Row Level Security & Permissions Matrix
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sport_competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixtures ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_events ENABLE ROW LEVEL SECURITY;

-- Helper function to check org role
CREATE OR REPLACE FUNCTION has_org_role(check_org_id UUID, check_role TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM organization_memberships
        WHERE org_id = check_org_id
          AND user_id = auth.uid()
          AND role = check_role
          AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS Policies
CREATE POLICY public_read_orgs ON organizations FOR SELECT USING (true);
CREATE POLICY public_read_competitions ON sport_competitions FOR SELECT USING (true);
CREATE POLICY public_read_fixtures ON fixtures FOR SELECT USING (true);
CREATE POLICY public_read_match_events ON match_events FOR SELECT USING (true);

-- Admin write policies
CREATE POLICY admin_manage_competitions ON sport_competitions
    FOR ALL USING (
        has_org_role((SELECT org_id FROM seasons WHERE id = season_id), 'admin') OR
        has_org_role((SELECT org_id FROM seasons WHERE id = season_id), 'owner')
    );

CREATE POLICY admin_manage_registrations ON registrations
    FOR ALL USING (
        has_org_role((SELECT org_id FROM seasons WHERE id = (SELECT season_id FROM sport_competitions WHERE id = sport_competition_id)), 'admin') OR
        has_org_role((SELECT org_id FROM seasons WHERE id = (SELECT season_id FROM sport_competitions WHERE id = sport_competition_id)), 'owner')
    );
