./build.oro bin
ninja -C bin
[ -f bin/foo ] || fail 'not found: bin/foo'
[ -f bin/bar ] || fail 'not found: bin/bar'
