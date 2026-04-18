#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/eisonAI.xcodeproj"
SCHEME="${SCHEME:-eisonAIUITests}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
TEST_IDENTIFIER="${TEST_IDENTIFIER:-eisonAIUITests/BrowserAgentAutomationUITests/testWikipediaOscarsAgentRun}"

xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:"$TEST_IDENTIFIER"
