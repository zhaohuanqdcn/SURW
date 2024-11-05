set -e

BIN=$(readlink -f $1)
shift

gdb -iex "set exec-wrapper env LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so" $BIN $@
