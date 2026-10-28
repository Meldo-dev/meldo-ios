#!/bin/zsh
# Runs the security regression tests on an iPhone simulator.
# Usage: scripts/security-tests.sh
set -u
cd "$(dirname "$0")/.."
failed=0
xcodegen generate --quiet || failed=1
sim=$(xcrun simctl list devices available | grep -m1 -oE 'iPhone [^(]+\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}')
if [[ -z ${sim:-} ]]; then
  echo "No iPhone simulator found."; failed=1
else
  xcodebuild test -project MeldePlanner.xcodeproj -scheme MeldePlanner \
    -destination "id=$sim" CODE_SIGNING_ALLOWED=NO \
    -only-testing:MeldePlannerTests/SecurityTests \
    -only-testing:MeldePlannerTests/AuditFixTests \
    -only-testing:MeldePlannerTests/DriveSyncTests 2>&1 | grep -E "✔|✘|passed|failed|error:|\*\* TEST" | grep -v "Failed to delete history" || failed=1
fi
[[ $failed == 0 ]] && echo "== All security tests passed" || echo "== Some security tests failed (see above)"
exit $failed
