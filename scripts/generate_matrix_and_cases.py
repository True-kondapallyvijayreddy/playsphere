# -*- coding: utf-8 -*-
import os
import shutil

target = "/Users/apple/Desktop/Work_Projects/PlaySphere/docs/season_tournament_e2e_validation_test_cases.md"
art = "/Users/apple/.gemini/antigravity/brain/b287a8d9-dd9d-4317-adfc-ca65b7da71f8/season_tournament_e2e_validation_test_cases.md"

f = open(target, "a", encoding="utf-8")

def p(txt=""):
    f.write(txt + "\n")

def tc(tc_id, title, role, screen, pre, steps, exp_ui, exp_be, edge):
    p(f"### {tc_id}: {title}")
    p(f"* **Perspective:** {role}")
    p(f"* **Screen / Location:** `{screen}`")
    p(f"* **Pre-conditions:** {pre}")
    p(f"* **Step-by-Step Procedure:**\n{steps}")
    p(f"* **Expected Result (UI & Feedback):** {exp_ui}")
    p(f"* **Expected Result (Backend & Data):** {exp_be}")
    p(f"* **Edge / Negative Scenarios:** {edge}")
    p("")

print("Matrix script ready")
