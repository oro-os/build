./build.oro bin
if ninja -C bin ; then
	fail 'expected a failure'
fi
