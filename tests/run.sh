#!/bin/bash
# Compila ed esegue i test del modello obiettivi in un ambiente isolato (non tocca i dati veri).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
swiftc -o "$T/goaltest" Sources/Common.swift Sources/GoalStore.swift tests/main.swift -framework Cocoa -framework WebKit
STUDYTIMER_GOALS="$T/goals.json" STUDYTIMER_DATA="$T/sessions.json" STUDYTIMER_SUITE="st.goaltest" "$T/goaltest"
defaults delete st.goaltest 2>/dev/null || true; rm -f ~/Library/Preferences/st.goaltest.plist; rm -rf "$T"
