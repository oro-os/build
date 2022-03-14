./build.oro bin
rm -f bin/{empty,hello,multi}
ninja -C bin
[ -f "bin/empty" ] || fail "missing bin/empty"
[ -f "bin/hello" ] || fail "missing bin/hello"
[ -f "bin/multi/empty" ] || fail "missing bin/multi/empty"
[ -f "bin/multi/hello" ] || fail "missing bin/multi/hello"
(diff --color=always -c empty bin/empty) || fail "unexpected contents: bin/empty"
(diff --color=always -c hello bin/hello) || fail "unexpected contents: bin/hello"
(diff --color=always -c empty bin/multi/empty) || fail "unexpected contents: bin/multi/empty"
(diff --color=always -c hello bin/multi/hello) || fail "unexpected contents: bin/multi/hello"
