#!/bin/sh
# Native macOS checks for shared walk logic; no device, simulator, or user data.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/glowalk-core.XXXXXX")
trap 'rm -rf "$verification_dir"' EXIT HUP INT TERM
verification_app="$verification_dir/Verify.app/Contents"
mkdir -p "$verification_app/MacOS" "$verification_app/Resources"
xcrun momc "$repo_root/GloWalk/Resources/GloWalk.xcdatamodeld" "$verification_app/Resources/GloWalk.momd"
cp "$repo_root/GloWalk/Resources/Taglines.json" "$verification_app/Resources/Taglines.json"
xcrun swiftc -parse-as-library -module-name GloWalk \
    "$repo_root/GloWalk/Extensions/L10n.swift" \
    "$repo_root/GloWalk/Models/WalkSession.swift" \
    "$repo_root/GloWalk/Models/PathPoint.swift" \
    "$repo_root/GloWalk/Models/WalkClock.swift" \
    "$repo_root/GloWalk/Models/NightMemoryProfile.swift" \
    "$repo_root/GloWalk/Models/NightMemoryRandom.swift" \
    "$repo_root/GloWalk/Models/PathProjector.swift" \
    "$repo_root/GloWalk/Models/Tagline.swift" \
    "$repo_root/GloWalk/Models/UserPreferences.swift" \
    "$repo_root/GloWalk/Services/Log.swift" \
    "$repo_root/scripts/WalkCoreVerification.swift" \
    -o "$verification_app/MacOS/verify"
"$verification_app/MacOS/verify"
