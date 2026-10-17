#!/bin/bash
# Pre-publish checklist. Run before tagging a release: ./scripts/check-release.sh
# Exits non-zero if anything a user would hit (dead link, wrong version, broken build) is off.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
pass() { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; fail=1; }
warn() { echo "  ⚠️  $1"; }

http_status() { curl -s -o /dev/null -w '%{http_code}' -L -m 15 "$1"; }

echo "Donation links"
KOFI=$(sed -n 's/.*static let kofiUsername = "\(.*\)".*/\1/p' Sources/MacScreenshot/HelpWindow.swift)
if [[ -z "$KOFI" ]]; then
    warn "Ko-fi not set: the app hides it; only GitHub Sponsors is offered (set Links.kofiUsername to add it)"
else
    case "$(http_status "https://ko-fi.com/$KOFI")" in
        200) pass "ko-fi.com/$KOFI is live" ;;
        403) warn "ko-fi.com blocks scripted checks; open https://ko-fi.com/$KOFI in a browser to confirm" ;;
        *)   bad "ko-fi.com/$KOFI doesn't load" ;;
    esac
    grep -q "^ko_fi: $KOFI$" .github/FUNDING.yml && pass "FUNDING.yml has Ko-fi" || bad "FUNDING.yml is missing 'ko_fi: $KOFI'"
    grep -q "ko-fi.com/$KOFI" README.md && pass "README links Ko-fi" || bad "README doesn't link ko-fi.com/$KOFI"
fi
SPONSORS_PUBLIC=$(gh api graphql -f query='{ user(login:"CJayXYZ"){ hasSponsorsListing } }' -q .data.user.hasSponsorsListing 2>/dev/null)
[[ "$SPONSORS_PUBLIC" == "true" ]] && pass "GitHub Sponsors profile is public" \
    || bad "GitHub Sponsors profile isn't public yet (finish it at github.com/sponsors/CJayXYZ/dashboard)"

echo "Version"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
grep -q "^## $VERSION " CHANGELOG.md && pass "CHANGELOG has $VERSION" || bad "CHANGELOG has no '## $VERSION' entry"
if git rev-parse "v$VERSION" >/dev/null 2>&1; then bad "tag v$VERSION already exists"; else pass "tag v$VERSION is free"; fi

echo "Privacy"
EMAIL=$(git config user.email)
[[ "$EMAIL" == *users.noreply.github.com ]] && pass "commits use a no-reply email" || bad "commits would publish '$EMAIL' (set a GitHub no-reply email for this repo)"

echo "Build"
if ./build.sh --release >/tmp/macscreenshot-release.log 2>&1; then
    pass "release build succeeded"
    ARCHS=$(lipo -archs build/MacScreenshot.app/Contents/MacOS/MacScreenshot)
    [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] && pass "universal binary ($ARCHS)" || bad "not universal ($ARCHS)"
    codesign --verify --deep --strict build/MacScreenshot.app 2>/dev/null && pass "code signature valid" || bad "code signature invalid"
    [[ -f "build/MacScreenshot-$VERSION.zip" ]] && pass "build/MacScreenshot-$VERSION.zip ready" || bad "release zip missing"
    grep -q "warning:" /tmp/macscreenshot-release.log && warn "compiler warnings, see /tmp/macscreenshot-release.log" || pass "no compiler warnings"
else
    bad "release build failed, see /tmp/macscreenshot-release.log"
fi

echo
if [[ $fail == 0 ]]; then echo "All checks passed. Ready to publish v$VERSION."; else echo "Fix the ❌ items before publishing."; fi
exit $fail
