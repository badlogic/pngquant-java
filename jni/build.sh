#!/bin/bash
set -e

export PATH=$PATH:~/.cargo/bin

BUILD=debug
BUILD_DIR="target"
CXX=g++
STRIP=strip
CXX_FLAGS="-c -Wall"
LINKER_FLAGS="-shared"
LIBRARIES="-L$BUILD_DIR -lm -lgifski"
OUTPUT_DIR="../src/main/resources/"
OUTPUT_PREFIX="lib"
OUTPUT_NAME="gifski-java"
OUTPUT_SUFFIX=".so"

function usage {
  cat <<EOF
Usage: $SELF [options]
Options:
  --build=[release|debug] Specifies the build type. If not set both release
                          and debug versions of the libraries will be built.
  --target=...            Specifies the target to build for. Supported
                          targets are macosx, linux-x86_64, linux-x86,
                          windows-x86, and windows-x86_64. If not set the
                          current host OS determines the targets.
  --help                  Displays this information and exits.
EOF
  exit $1
}

+() { :;} 2> /dev/null; trace() { (PS4=; set -x; "$@";{ set +x; } 2> /dev/null); "$@";}

while [ "${1:0:2}" = '--' ]; do
  NAME=${1%%=*}
  VALUE=${1#*=}
  case $NAME in
    '--target') TARGET="$VALUE" ;;
    '--build') BUILD="$VALUE" ;;
    '--help')
      usage 0
      ;;
    *)
      echo "Unrecognized option or syntax error in option '$1'"
      usage 1
      ;;
  esac
  shift
done

if [ "x$TARGET" = 'x' ]; then
    echo "Please specify a target with --target=<target>: macosx, linux-x86, linux-x86_64, windows-x86, windows-x86_64"
    exit 1
fi

if [ "x$TARGET" != 'x' ]; then
    OS=${TARGET%%-*}
    ARCH=${TARGET#*-}

    if [ "$ARCH" = "x86" ]; then
        CXX_FLAGS="$CXX_FLAGS -m32"
        LINKER_FLAGS="$LINKER_FLAGS -m32"
    else
        CXX_FLAGS="$CXX_FLAGS -m64"
        LINKER_FLAGS="$LINKER_FLAGS -m64"
        OUTPUT_NAME="$OUTPUT_NAME""64"
    fi

    if [ "$OS" = "windows" ]; then
        CXX="i686-w64-mingw32-g++"
        LINKER_FLAGS="-Wl,--kill-at -static-libgcc -static-libstdc++ $LINKER_FLAGS"
        JNI_MD="win32"
        LIBRARIES="$LIBRARIES -lwsock32 -lws2_32 -ldbghelp -luserenv"
        OUTPUT_PREFIX=""
        OUTPUT_SUFFIX=".dll"
        if [ "$ARCH" = "x86_64" ]; then
            CXX="x86_64-w64-mingw32-g++"
            STRIP="x86_64-w64-mingw32-strip"
            RUST_TARGET="x86_64-pc-windows-gnu"
        else
            RUST_TARGET="i686-pc-windows-gnu"
        fi
    fi

    if [ "$OS" = "linux" ]; then
        CXX_FLAGS="$CXX_FLAGS -fPIC"
        JNI_MD="linux"
        if [ "$ARCH" = "x86_64" ]; then
            RUST_TARGET="x86_64-unknown-linux-gnu"
        else
            RUST_TARGET="i686-unknown-linux-gnu"
        fi
    fi

    if [ "$OS" = "macosx" ]; then
        CXX_FLAGS="$CXX_FLAGS -fPIC"
        JNI_MD="mac"
        OUTPUT_SUFFIX=".dylib"
        RUST_TARGET="x86_64-apple-darwin"
    fi

    if [ "$BUILD" = "debug" ]; then
        CXX_FLAGS="$CXX_FLAGS -g"
    else
        CXX_FLAGS="$CXX_FLAGS -O2"
    fi
fi


CXX_SOURCES=`find src -name *.cpp`
HEADERS="-I./ -Ijni-headers -Ijni-headers/${JNI_MD} -Igifski/"

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR
mkdir -p $OUTPUT_DIR

echo "--- Compiling for $TARGET, build type $BUILD"
echo "------ Compiling Gifski Rust"
cd gifski
if [ "$BUILD" = "release" ]; then
    RUST_BUILD="--$BUILD"
fi
trace cargo build --target=$RUST_TARGET $RUST_BUILD --lib
cp target/$RUST_TARGET/$BUILD/*.a ../$BUILD_DIR 2>/dev/null | true
cp target/$RUST_TARGET/$BUILD/*.lib ../$BUILD_DIR 2>/dev/null | true
cd ..
echo


echo "------ Compiling C++ sources"
for f in $CXX_SOURCES; do
    OBJECT_FILE=$BUILD_DIR/`basename $f .c`
    trace $CXX $CXX_FLAGS $HEADERS "$f" -o $OBJECT_FILE.o
done
echo

echo "--- Linking & stripping"
LINKER=$CXX
OBJ_FILES=`find $BUILD_DIR -name *.o`
OUTPUT_FILE="$OUTPUT_DIR$OUTPUT_PREFIX$OUTPUT_NAME$OUTPUT_SUFFIX"
trace pwd
trace $LINKER $OBJ_FILES $LIBRARIES $LINKER_FLAGS -o "$OUTPUT_FILE"

echo

rm -rf $BUILD_DIR