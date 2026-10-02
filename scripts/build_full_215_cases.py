import os
import shutil

target = "/Users/apple/Desktop/Work_Projects/PlaySphere/docs/season_tournament_e2e_validation_test_cases.md"
art = "/Users/apple/.gemini/antigravity/brain/b287a8d9-dd9d-4317-adfc-ca65b7da71f8/season_tournament_e2e_validation_test_cases.md"

os.makedirs(os.path.dirname(target), exist_ok=True)
os.makedirs(os.path.dirname(art), exist_ok=True)

f = open(target, "w", encoding="utf-8")

def w(s=""):
    f.write(s + "\n")

w("# PlaySphere Master 200+ Test Case Specification: Season & Tournament Flow")
w("## Ultra-Detailed Button-by-Button & Functional E2E Quality Assurance Guide")
w("")
w("**Document ID:** `PS-QA-E2E-200-SPEC-2026-V5`  ")
w("**Target Platform:** PlaySphere Multi-Sport Operating System (Flutter Web/iOS/Android + Firebase Cloud Architecture)  ")
w("**Total Test Cases:** 215 Granular Test Cases  ")
w("**Coverage Breakdown:**")
w("- **PART 1: SEASON CREATOR & HOST ADMIN SIDE (125 Test Cases: TC-CREATOR-001 to TC-CREATOR-125)**")
w("- **PART 2: PARTICIPATING CLUBS & PLAYERS SIDE (90 Test Cases: TC-PLAYER-001 to TC-PLAYER-090)**")
w("")
w("---")
w("")
w("### Test Execution Roles & Matrix")
w("| Role | Device | Account | Responsibilities |")
w("|:---|:---|:---|:---|")
w("| **Host Club Owner / Admin** | D1 | `admin@pstesthost.org` | Season setup, event life-cycle, house management, grounds, scheduling, publishing, entry approvals |")
w("| **Host Regular Member** | D2 | `player2@pstesthost.org` | Member of host club, house athlete, individual singles registrant |")
w("| **Dual-Club Athlete** | D3 | `player3@pstesthost.org` | Multi-sport competitor (Cricket & Badminton), RSVP responder |")
w("| **Visiting Club Owner / Captain** | D4 | `owner@psvisitors.org` | External club owner, invite recipient, RSVP poll author, multi-team submitter |")
w("")
w("---")
w("")

def add_tc(tc_id, title, role, screen, pre, steps, exp_ui, exp_be, edge):
    w(f"### {tc_id}: {title}")
    w(f"* **Perspective:** {role}")
    w(f"* **Screen / Location:** `{screen}`")
    w(f"* **Pre-conditions:** {pre}")
    w(f"* **Step-by-Step Procedure:**\n{steps}")
    w(f"* **Expected Result (UI & Feedback):** {exp_ui}")
    w(f"* **Expected Result (Backend & Data):** {exp_be}")
    w(f"* **Edge / Negative Scenarios:** {edge}")
    w("")

# Write Suites
print("Writing suites...")
