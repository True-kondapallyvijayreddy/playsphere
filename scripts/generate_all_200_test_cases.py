import sys
import os

target = "/Users/apple/Desktop/Work_Projects/PlaySphere/docs/season_tournament_e2e_validation_test_cases.md"
art = "/Users/apple/.gemini/antigravity/brain/b287a8d9-dd9d-4317-adfc-ca65b7da71f8/season_tournament_e2e_validation_test_cases.md"

os.makedirs(os.path.dirname(target), exist_ok=True)
os.makedirs(os.path.dirname(art), exist_ok=True)

print("Starting generation...")
