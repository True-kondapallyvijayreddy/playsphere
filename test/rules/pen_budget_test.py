"""Does a REAL fixture document blow Firestore's 1,000-expression budget?

`pen_rules_test.py` seeds a skeletal fixture: no officials, no line-ups, no
squad calls, no participating clubs. That is not what a match looks like in
production, and the budget is spent per EXPRESSION EVALUATED, not per rule —
so every extra field that a statement inspects on the way past, and every
`get()` a fallthrough performs, costs budget that a thin fixture never spends.

An overrun is not reported as an overrun. It is reported as permission-denied,
which the pad then renders as a refusal to score. So a rules file that passes
every emulator test on a thin document can still refuse every tap on a real
one, and nothing in the test suite would notice.

This drives the same score write against a fixture carrying the load a real
one does, and prints the emulator's own reason when it fails.

    firebase emulators:exec --only firestore --project demo-playsphere \
      --config firebase.rules-test.json "python3 test/rules/pen_budget_test.py 8099"
"""
import base64, json, sys, urllib.error, urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "8099"
PROJECT = "demo-playsphere"
BASE = f"http://127.0.0.1:{PORT}/v1/projects/{PROJECT}/databases/(default)/documents"

ORG, ORG2, COMP, FIX = "org1", "org2", "comp1", "fix1"
OWNER, UMP = "uOwner", "uUmp"


def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")


def token(uid):
    return ".".join([
        b64({"alg": "none", "typ": "JWT"}),
        b64({"iss": f"https://securetoken.google.com/{PROJECT}", "aud": PROJECT,
             "sub": uid, "user_id": uid, "email_verified": True,
             "firebase": {"sign_in_provider": "custom", "identities": {}}}),
        "",
    ])


def call(method, path, body=None, auth="owner", params=""):
    req = urllib.request.Request(
        f"{BASE}/{path}{params}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {auth}"})
    try:
        return urllib.request.urlopen(req).status, ""
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def s(v):
    return {"stringValue": v}


def arr(vals):
    return {"arrayValue": {"values": vals}}


def player(i):
    return {"mapValue": {"fields": {"id": s(f"p{i}"), "name": s(f"Player {i}"),
                                    "role": s("all_rounder")}}}


def official(uid, i):
    return {"mapValue": {"fields": {
        "uid": s(uid), "name": s(f"Official {i}"), "role": s("umpire"),
        "grantedScoringAccess": {"booleanValue": False}}}}


def seed():
    for org in (ORG, ORG2):
        call("PATCH", f"orgs/{org}", {"fields": {
            "name": s("Club"), "visibility": s("public"),
            "ownerUid": s(OWNER), "orgType": s("school")}})
        for uid, role in [(OWNER, "owner"), (UMP, "judge_scorer")]:
            call("PATCH", f"orgs/{org}/members/{uid}", {"fields": {
                "status": s("active"), "role": s(role), "uid": s(uid),
                "displayName": s(uid)}})
    call("PATCH", f"orgs/{ORG}/competitions/{COMP}", {"fields": {
        "name": s("Cup"), "orgId": s(ORG), "format": s("knockout"),
        "createdBy": s(OWNER), "sportId": s("cricket")}})


def reset(fat):
    """fat=False reproduces pen_rules_test's thin fixture; True is realistic."""
    f = {
        "orgId": s(ORG), "compId": s(COMP),
        "entrantAId": s("a"), "entrantBId": s("b"),
        "entrantAName": s("Anand"), "entrantBName": s("Bhavani"),
        "status": s("live"), "lastSeq": {"integerValue": "4"},
        "summary": s("2-2"), "isDraw": {"booleanValue": False},
        "winnerEntrantId": {"nullValue": None},
        "scoreState": {"mapValue": {"fields": {"a": {"integerValue": "2"},
                                               "b": {"integerValue": "2"}}}},
        "scorerUids": arr([s(UMP)]),
        "activeScorerUid": s(UMP),
        "activeScorerDeviceId": s("dev-1"),
        "officials": arr([]),
        "lineupA": arr([]), "lineupB": arr([]),
        "isDraft": {"booleanValue": False},
        "venue": s("Court 1"),
    }
    if fat:
        f.update({
            "officials": arr([official(f"uOff{i}", i) for i in range(4)]),
            "lineupA": arr([player(i) for i in range(11)]),
            "lineupB": arr([player(i) for i in range(11, 22)]),
            "playerUids": arr([s(f"pu{i}") for i in range(22)]),
            "participantOrgIds": arr([s(ORG), s(ORG2)]),
            "squadCallA": {"mapValue": {"fields": {
                "open": {"booleanValue": False},
                "capacity": {"integerValue": "11"},
                "locked": {"booleanValue": True},
                "count": {"integerValue": "11"}}}},
            "squadCallB": {"mapValue": {"fields": {
                "open": {"booleanValue": False},
                "capacity": {"integerValue": "11"},
                "locked": {"booleanValue": True},
                "count": {"integerValue": "11"}}}},
            "sourceType": s("season"), "sourceId": s("tour1"),
            "tournamentId": s("tour1"),
            "resultState": s("none"),
            "readiness": s("ready"),
            "bracket": s("group"), "round": {"integerValue": "1"},
            "courtName": s("Court 1"), "notes": s("n" * 200),
        })
    call("PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}", {"fields": f})


def score(uid, seq=5):
    return call(
        "PATCH", f"orgs/{ORG}/competitions/{COMP}/fixtures/{FIX}",
        {"fields": {"lastSeq": {"integerValue": str(seq)}, "status": s("live"),
                    "summary": s("3-2"),
                    "scoreState": {"mapValue": {"fields": {
                        "a": {"integerValue": "3"},
                        "b": {"integerValue": "2"}}}}}},
        auth=token(uid),
        params=("?updateMask.fieldPaths=lastSeq&updateMask.fieldPaths=status"
                "&updateMask.fieldPaths=summary&updateMask.fieldPaths=scoreState"))


seed()
fails = 0
for label, fat in [("thin fixture (what the suite tests)", False),
                   ("REAL fixture (officials, line-ups, squads, two clubs)", True)]:
    reset(fat)
    code, detail = score(UMP)
    ok = code == 200
    fails += 0 if ok else 1
    print(("PASS  " if ok else "FAIL  ") + f"[{code}] pen holder scores a {label}")
    if not ok:
        print("      " + detail.replace("\n", " ")[:340])

sys.exit(0 if fails == 0 else 1)
