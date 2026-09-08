#!/bin/sh
# harness/tools/oracle_build.sh -- rebuild the instrumented oracle at the pin.
#
# ★★★★★ THE INVOCATION WAS IN NOBODY'S FILE. scummvm.pin records the configure line and
# `make -j2`, but not the PATH prepend that makes them work -- and the toolchain is at
# C:\Projects\2600em\tools\mingw64\bin, vendored into a SIBLING PROJECT's tree, off PATH and in no
# standard location. That absence already cost this project four tasks, during which the pin
# asserted "no C++ toolchain on the Windows host" while a complete MinGW-w64 sat there [X-32].
# ★★★ So the recipe lives here, runnable, rather than in a shell history [L-45].
#
# ★★ It PREPENDS to PATH rather than replacing it: replacing it removes coreutils and the build
# dies on a missing `tail` long after the compiler was found.
#
# usage:  sh harness/tools/oracle_build.sh
set -e
export PATH="/c/Projects/2600em/tools/mingw64/bin:$PATH"
cd /c/Users/jayse/DEV/scummvm

echo "=== toolchain ==="
g++ --version | head -1

# ★★★★ `mingw32-make`, NOT `make`. scummvm.pin's [build] line says `make -j2` and that is the WSL
# recipe; the native toolchain ships mingw32-make and the pin's own [build-native] note says
# `mingw32-make -j8`. **Two recipes in one file, and the one at the top is the one that fails.**
# Recorded here as the runnable one so the next reader does not repeat the five minutes.
# ★ Incremental only: the two local steps [build-native] describes (dists/scummvm.o's sed, and the
# resource rule) are needed after a CLEAN configure, and the objects already exist.
echo "=== make ==="
mingw32-make -j8 > /tmp/oracle_build.log 2>&1 || {
    echo "★★★ BUILD FAILED -- last 30 lines:"
    tail -30 /tmp/oracle_build.log
    exit 1
}
tail -6 /tmp/oracle_build.log
echo "=== binary ==="
ls -l scummvm.exe | awk '{print "  " $5 " bytes  " $6 " " $7 " " $8}'
