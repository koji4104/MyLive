#!/bin/bash

if which $(pwd)/OpenSSL-for-iPhone >/dev/null; then
  echo ""
else
  git clone git@github.com:krzyzanowskim/OpenSSL.git
fi

pushd OpenSSL-for-iPhone
./build-libssl.sh
popd
