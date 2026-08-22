"""Behavioural check of the scoring-pen rules against the Firestore emulator.

Run it:

    firebase emulators:exec --only firestore --project demo-playsphere \
      --config firebase.rules-test.json "python3 test/rules/pen_rules_test.py 8099"

## Why this exists as well as the Dart tests

`Fixture.mayScoreNow` and the service guard are the client's answer to "may
this person score right now", and a client's answer is advice. The rule is the
law, and it is the only thing standing between a determined second device and
the match. Compiling is not the question either — `emulators:exec` starts
happily on a rules file the emulator will later refuse to load — so this drives
real writes as real signed-in users and asserts the verdicts.

The cases that matter are the two the old rules got wrong: a second ASSIGNED
scorer (allowed before, because `scorerUids` is a list and everyone on it was
equal), and the OWNER (allowed before, through the broad organizer branch,
which meant handing an umpire the pen and then editing the score from the
office was something the rules permitted).

No script runs this in CI yet; it needs the Firestore emulator and a JDK.
"""
import base64, json, sys, urllib.error, urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "8099"
PROJECT = "demo-playsphere"
BASE = f"http://127.0.0.1:{PORT}/v1/projects/{PROJECT}/databases/(default)/documents"

ORG, COMP, FIX = "org1", "comp1", "fix1"
OWNER, UMP, ADMIN2, UMP2 = "uOwner", "uUmp", "uAdmin2", "uUmp2"
# A plain member with no scoring role, used for the line-up case below.
PLAYER = "uPlayer"


def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")


def token(uid):
    return ".".join([
        b64({"alg": "none", "typ": "JWT"}),
        b64({
            "iss": f"https://securetoken.google.com/{PROJECT}",
            "aud": PROJECT, "sub": uid, "user_id": uid,
            "email_verified": True, "firebase": {"sign_in_provider": "custom",
                                                 "identities": {}},
        }),
        "",
    ])


def call(method, path, body=None, auth="owner", params=""):
    req = urllib.request.Request(
        f"{BASE}/{path}{params}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {auth}"},
    )
    try:
        return urllib.request.urlopen(req).status, None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def s(v):
    return {"stringValue": v}


def seed():
    call("PATCH", f"orgs/{ORG}", {"fields": {
        "name": s("Test Club"), "visibility": s("public"),
        "ownerUid": s(OWNER), "orgType": s("school")}})
    for uid, role in [(OWNER, "owner"), (UMP, "judge_scorer"),
                      (ADMIN2, "admin"), (UMP2, "judge_scorer"),
                      (PLAYER, "member")]:
        call("PATCH", f"orgs/{ORG}/members/{uid}",
             {"fields": {"status": s("active"), "role": s(role),
                         "uid": s(uid), "displayName": s(uid)}})
    call("PATCH", f"orgs/{ORG}/competitions/{COMP}", {"fields": {
        "name": s("Cup"), "orgId": s(ORG), "format": s("knockout"),
        "createdBy": s(OWNER), "sportId": s("badminton")}})


def reset_fixture(active_uid, scorers=None):
    holder = s(active_uid) if active_uid else {"nullValue": None}
    scorers = [UMP, ADMIN2, UMP2] if scorers is None else scorers
    call("PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}", {"fields": {
        "orgId": s(ORG), "compId": s(COMP),
        "entrantAId": s("a"), "entrantBId": s("b"),
        "entrantAName": s("Anand"), "entrantBName": s("Bhavani"),
        "status": s("live"), "lastSeq": {"integerValue": "4"},
        "summary": s("2-2"), "isDraw": {"booleanValue": False},
        "winnerEntrantId": {"nullValue": None},
        "scoreState": {"mapValue": {"fields": {"a": {"integerValue": "2"},
                                               "b": {"integerValue": "2"}}}},
        "scorerUids": {"arrayValue": {"values": [s(u) for u in scorers]}},
        "activeScorerUid": holder,
        "activeScorerDeviceId": s("dev-1") if active_uid else {"nullValue": None},
        "officials": {"arrayValue": {"values": []}},
        "lineupA": {"arrayValue": {"values": [
            {"mapValue": {"fields": {"id": s(PLAYER),
                                     "name": s("Player")}}}]}},
        "lineupB": {"arrayValue": {"values": []}},
        "isDraft": {"booleanValue": False},
        "venue": s("Court 1"),
    }})


def score_write(uid, seq=5):
    return call(
        "PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}",
        {"fields": {"lastSeq": {"integerValue": str(seq)},
                    "status": s("live"), "summary": s("3-2"),
                    "scoreState": {"mapValue": {"fields": {
                        "a": {"integerValue": "3"},
                        "b": {"integerValue": "2"}}}}}},
        auth=token(uid),
        params=("?updateMask.fieldPaths=lastSeq&updateMask.fieldPaths=status"
                "&updateMask.fieldPaths=summary"
                "&updateMask.fieldPaths=scoreState"),
    )


def pen_write(actor, new_holder):
    return call(
        "PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}",
        {"fields": {"activeScorerUid": s(new_holder),
                    "activeScorerDeviceId": {"nullValue": None},
                    "penGrantedByUid": s(actor)}},
        auth=token(actor),
        params=("?updateMask.fieldPaths=activeScorerUid"
                "&updateMask.fieldPaths=activeScorerDeviceId"
                "&updateMask.fieldPaths=penGrantedByUid"),
    )


def claim_write(actor, scorers):
    return call(
        "PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}",
        {"fields": {"activeScorerUid": s(actor),
                    "activeScorerDeviceId": s("dev-9"),
                    "penGrantedByUid": s(actor),
                    "scorerUids": {"arrayValue": {"values": [s(u) for u in scorers]}}}},
        auth=token(actor),
        params=("?updateMask.fieldPaths=activeScorerUid"
                "&updateMask.fieldPaths=activeScorerDeviceId"
                "&updateMask.fieldPaths=penGrantedByUid"
                "&updateMask.fieldPaths=scorerUids"),
    )


def venue_write(actor):
    return call(
        "PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}",
        {"fields": {"venue": s("Court 2")}},
        auth=token(actor),
        params="?updateMask.fieldPaths=venue",
    )


results = []


def check(name, got, want_allow):
    code = got[0]
    ok = (code == 200) if want_allow else (code == 403)
    results.append((ok, name, code, got[1] if not ok else ""))


seed()

reset_fixture(UMP)
check("the pen holder may score", score_write(UMP), True)

reset_fixture(UMP)
check("a second assigned scorer may not score", score_write(ADMIN2), False)

reset_fixture(UMP)
check("the OWNER may not overwrite the score while somebody holds the pen",
      score_write(OWNER), False)

reset_fixture(UMP)
check("the owner may still reschedule while somebody holds the pen",
      venue_write(OWNER), True)

reset_fixture(UMP)
check("an owner may move the pen", pen_write(OWNER, ADMIN2), True)

reset_fixture(UMP)
# uUmp2 is a judge_scorer assigned to this match: eligible to score, with
# no authority over who scores. Taking the pen off a colleague mid-match is
# an organizer's decision — that is the whole reason the handover is recorded.
check("a scorer may not take the pen off another scorer",
      pen_write(UMP2, UMP2), False)

reset_fixture(UMP)
check("a scorer who is not the holder may not score", score_write(UMP2), False)

reset_fixture(None)
check("an assigned scorer may claim a free pen", pen_write(UMP, UMP), True)

reset_fixture(None)
check("an unheld pen leaves scoring open to an assigned scorer",
      score_write(ADMIN2), True)

# ── The draw-generated fixture: nobody is assigned yet ────────────────────
#
# `CompetitionRepository.generateDraw` defaults `defaultScorerUids` to const []
# and no caller passes it, so every fixture a draw produces starts with an
# EMPTY scorerUids. That is the state a club owner meets when they create a
# competition and walk up to the first match, and it is the state the reported
# "this device is not the one scoring this match" came from.
#
# An organizer may score it directly while the pen is free — `mayScoreNow`
# falls back to the role test for exactly this reason, so the person who walks
# up to an unassigned match is not blocked by a list nobody filled in. Claiming
# the pen is the other route, and it is the one the pad actually takes.
#
# Both are pinned here because the DEPLOYED rules failed the claim with
# "maximum of 1000 expressions" — the budget overrun that surfaces to a scorer
# as permission-denied, and to the pad as "this device is not the one scoring
# this match".

reset_fixture(None, scorers=[])
check("an organizer may score an unassigned match while the pen is free",
      score_write(OWNER), True)

reset_fixture(None, scorers=[])
check("an organizer may claim the pen on their own unassigned match",
      claim_write(OWNER, [OWNER]), True)
check("and may then score it", score_write(OWNER), True)

# ── The line-up player ────────────────────────────────────────────────────
#
# Nothing on the server reads lineupA/lineupB when deciding who may score, and
# it must stay that way: a line-up is client-written match data, so a rule that
# trusted it would let anyone able to edit a line-up add themselves and score.
#
# The pad used to admit line-up players anyway (`isLineupPlayer`), which handed
# a plain member a fully working pad on which every tap came back refused. The
# client no longer does that; this pins the server half, so that if the drift
# is ever "fixed" from the rules side instead, it fails here.

reset_fixture(None, scorers=[])
check("a line-up player who is not assigned may not score",
      score_write(PLAYER), False)

for ok, name, code, detail in results:
    print(("PASS  " if ok else "FAIL  ") + f"[{code}] {name}")
    if detail:
        print("      " + detail.replace("\n", " ")[:220])

print("SUMMARY", sum(1 for r in results if r[0]), "/", len(results))
sys.exit(0 if all(r[0] for r in results) else 1)
