#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

runtest() {
	printf -- '----------- \x1b[95;1m%s\x1b[m -----------\n' "$1" >&2

	# Circumvent re-building the harness over and over again.
	if [ "$1" != "empty" ] && [ -f empty/bin/.oro/build ]; then
		mkdir -p "$1/bin/.oro"
		cp -u empty/bin/.oro/build "$1/bin/.oro/build"
	fi

	# If there is an override script, run that. Otherwise,
	# just run the build and do `all test`.
	if [ -f "$1/test.sh" ]; then
		(cd "$1" && "./test.sh")
	else
		(cd "$1" && ./build.oro bin)
		ninja -C "$1/bin" all test
	fi
}

# EMPTY MUST COME FIRST!
runtest empty
runtest print
