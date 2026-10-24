#!/usr/bin/env bash
# Build Stoa-<version>.zip: one top-level Stoa/ folder with the addon files only.
# Usage: Tools/package.sh [git-ref]   (default HEAD; output goes to dist/)
# The release workflow runs this same script, so local and CI builds match.
# Keep the exclude list in step with .pkgmeta.
set -euo pipefail

cd "$(dirname "$0")/.."
ref="${1:-HEAD}"

# Version comes from the TOC as committed at that ref.
version="$(git show "$ref:Stoa.toc" | sed -n 's/^## Version:[[:space:]]*//p' | tr -d '\r' | head -n 1)"
if [ -z "$version" ]; then
	echo "No '## Version:' line in Stoa.toc at $ref" >&2
	exit 1
fi

out="dist/Stoa-$version.zip"
mkdir -p dist
rm -f "$out"

# Only tracked files are packed, so stray local files never slip in.
git archive --format=zip --prefix=Stoa/ -o "$out" "$ref" -- . \
	':(exclude).github' \
	':(exclude)Tools' \
	':(exclude)docs' \
	':(exclude).gitignore' \
	':(exclude).gitattributes' \
	':(exclude).pkgmeta'

echo "Built $out"
