#!/usr/bin/env bash
# Copyright (C) 2022 National Cyber and Information Security Agency of the Czech Republic
# Unfortunately, PHP packages from CentOS repos missing some required extensions, so we have to build them
set -e

# Enable GCC Toolset version 13
source scl_source enable gcc-toolset-13

set -o xtrace

download_and_check () {
  curl --proto '=https' --tlsv1.3 -sS --location --fail -o package.tar.gz "$1"
  echo "$2 package.tar.gz" | sha256sum -c
  tar zxf package.tar.gz --strip-components=1
  rm -f package.tar.gz
}

# Install required packages for build
dnf install -y --setopt=tsflags=nodocs --setopt=install_weak_deps=False php-devel brotli-devel diffutils file ssdeep-devel

# Build modules with march optimised for x86-64-v2
NPROC=$(nproc)
ARCH=$(uname -i)
if [ "$ARCH" == 'x86_64' ]; then
  MARCH="-march=x86-64-v2";
else
  MARCH="";
fi

DEFAULT_FLAGS="-O2 -g -Wl,-z,relro,-z,now -flto=auto -fstack-protector-strong ${MARCH}"

mkdir /build/php-modules/

# Compile simdjson
mkdir /tmp/simdjson
cd /tmp/simdjson
download_and_check https://github.com/crazyxman/simdjson_php/releases/download/3.0.0/simdjson-3.0.0.tgz 23cdf65ee50d7f1d5c2aa623a885349c3208d10dbfe289a71f26bfe105ea8db9
phpize
CPPFLAGS="$DEFAULT_FLAGS" ./configure --silent
make -j$NPROC
mv modules/*.so /build/php-modules/

# Compile igbinary
mkdir /tmp/igbinary
cd /tmp/igbinary
download_and_check https://github.com/igbinary/igbinary/archive/refs/tags/3.2.14.tar.gz 3dd62637667bee9328b3861c7dddc754a08ba95775d7b57573eadc5e39f95ac6
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent --enable-igbinary
make -j$NPROC
make install # `make install` is necessary, so redis extension can be compiled with `--enable-redis-igbinary`
mv modules/*.so /build/php-modules/

# Compile zstd library and zstd extension
mkdir /tmp/zstd
cd /tmp/zstd
download_and_check https://github.com/kjdev/php-ext-zstd/archive/refs/tags/0.13.3.tar.gz 547f84759c2177f4415ae4a5d5066f09d2979f06aa2b3b4b97b42c0990a1efc5
cd zstd
download_and_check https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz 8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1
cd ..
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent
make --silent -j$NPROC
mv modules/*.so /build/php-modules/

# Compile redis
mkdir /tmp/redis
cd /tmp/redis
download_and_check https://github.com/phpredis/phpredis/archive/refs/tags/6.0.2.tar.gz 786944f1c7818cc7fd4289a0d0a42ea630a07ebfa6dfa9f70ba17323799fc430
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent --enable-redis-igbinary
#./configure --silent --enable-redis-igbinary
make -j$NPROC
mv modules/*.so /build/php-modules/

# Compile ssdeep
mkdir /tmp/ssdeep
cd /tmp/ssdeep
download_and_check https://github.com/JakubOnderka/pecl-text-ssdeep/archive/3a2e2d9e5d58fe55003aa8b1f31009c7ad7f54e0.tar.gz 275bb3d6ed93b5897c9b37dac358509c3696239f521453d175ac582c81e23cbb
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent --with-ssdeep=/usr --with-libdir=lib64
make -j$NPROC
mv modules/*.so /build/php-modules/

# Compile brotli
mkdir /tmp/brotli
cd /tmp/brotli
download_and_check https://github.com/kjdev/php-ext-brotli/archive/48bf4071d266c556d61684e07d40d917f61c9eb7.tar.gz c145696965fac0bacd6b5ffef383eaf7a67539e9a0ed8897ab1632ca119510c6
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent --with-libbrotli
make -j$NPROC
mv modules/*.so /build/php-modules/

# Compile snuffleupagus
mkdir /tmp/snuffleupagus
cd /tmp/snuffleupagus
download_and_check https://github.com/jvoisin/snuffleupagus/archive/refs/tags/v0.11.0.tar.gz 7ed7dd3aca0a8f0971e87b56c19c60a1a4d654ee4cbbee9a5091b9d4cca28a34
cd src
phpize
CFLAGS="$DEFAULT_FLAGS" ./configure --silent --enable-snuffleupagus
make -j$NPROC
mv modules/*.so /build/php-modules/

# Remove debug symbols from binaries
strip /build/php-modules/*.so

# Cleanup
# 2022-05-06: Temporary disabled since stream8 has broken packages
# dnf history undo -y 0
