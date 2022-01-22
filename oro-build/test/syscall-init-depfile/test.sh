./build.oro bin
ninja -C bin
[ -f bin/foo/bar ] || fail 'not found: bin/foo/bar'
[ -f bin/foo/bar.d ] || fail 'not found: bin/foo/bar.d'
(printf 'foo/bar:\n' | diff --color=always -c - bin/foo/bar.d) || fail "unexpected contents: bin/foo/bar.d"
