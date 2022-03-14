#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
fail() {
	printf '\x1b[91;1mFAIL:\x1b[m %s\n' "$*" >&2
	return 1
}

export -f fail

runtest() {
	printf -- '----------- \x1b[95;1m%s\x1b[m -----------\n' "$1" >&2

	if [ "$1" != "empty" ]; then
		# Clear out the bin directory
		rm -rf "$1/bin"

		# Circumvent re-building the harness over and over again.
		if [ -f empty/bin/.oro/build ]; then
			mkdir -p "$1/bin/.oro"
			cp -u empty/bin/.oro/build "$1/bin/.oro/build"
		fi
	fi

	# If there is an override script, run that. Otherwise,
	# just run the build and do `all test`.
	if [ -f "$1/test.sh" ]; then
		(cd "$1" && bash -xeuo pipefail "./test.sh")
	else
		(cd "$1" && ./build.oro bin)
		ninja -C "$1/bin" all test
	fi
}

# EMPTY MUST COME FIRST!
runtest empty
runtest print
runtest builtin-touch
runtest builtin-pass
runtest builtin-fail
runtest globals-type
runtest globals-type-iscallable
runtest globals-startswith
runtest globals-endswith
runtest globals-syscall
runtest globals-prefix
runtest globals-norm-single
runtest globals-norm-singleopt
runtest globals-norm-singleinput
runtest globals-norm-singleinputopt
runtest path-basename
runtest syscall-init-depfile
runtest syscall-cp
