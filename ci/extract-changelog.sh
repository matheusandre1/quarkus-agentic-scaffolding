#!/usr/bin/env bash
# Print the CHANGELOG.md section for one version, without its heading.
#
#   extract-changelog.sh v0.14.0      # leading "v" optional
#
# Used as the body of the matching GitHub release, so the release notes and the
# changelog can never drift apart. Exits non-zero when the version has no section,
# which is what makes it safe to call from the release workflow.
set -euo pipefail

version=${1:?usage: extract-changelog.sh <version>}
version=${version#v}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
changelog="${CHANGELOG_FILE:-$script_dir/../CHANGELOG.md}"

if [ ! -f "$changelog" ]; then
  echo "No changelog at $changelog" >&2
  exit 1
fi

# Print lines after the "## v<version> — ..." heading, stopping at the next "## v".
section=$(awk -v want="$version" '
  # Heading of the section we want: start capturing (but skip the heading itself).
  $0 ~ "^## v" want "([^0-9.]|$)" { capture = 1; next }
  # Any later version heading ends it.
  capture && /^## v[0-9]/ { exit }
  capture { print }
' "$changelog")

# Trim leading and trailing blank lines.
section=$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$section" ]; then
  echo "No CHANGELOG section found for v$version" >&2
  exit 1
fi

printf '%s\n' "$section"
