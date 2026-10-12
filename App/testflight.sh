#!/bin/sh
# Archive the iPad app and upload it to App Store Connect for TestFlight.
#
#   App/testflight.sh TEAM_ID
#
# Needs Xcode signed in to the paid developer account (Settings → Accounts)
# and the app record created in App Store Connect. The build number is the
# commit count, so every upload from a new commit is accepted.
set -eu

TEAM=${1:?usage: testflight.sh TEAM_ID}
cd "$(dirname "$0")"
BUILD=$(git rev-list --count HEAD)
OUT=build/testflight
rm -rf "$OUT"
mkdir -p "$OUT"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "Archiving build $BUILD for team $TEAM…"
xcodebuild -project Bloodstones.xcodeproj -scheme Bloodstones -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$OUT/Bloodstones.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" \
    -allowProvisioningUpdates archive

echo "Uploading…"
xcodebuild -exportArchive -archivePath "$OUT/Bloodstones.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" \
    -allowProvisioningUpdates

echo "Uploaded build $BUILD. It appears in TestFlight once Apple finishes processing (often 10–30 minutes)."
