#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C CCACHE_DISABLE=1

trap 'chown -R "$HOST_UID:$HOST_GID" /results' EXIT

rm -f /results/baseline.{txt,bin} /results/optimized.{txt,bin} \
    /results/baseline-time-{1,2,3}.txt /results/optimized-time-{1,2,3}.txt \
    /results/baseline-build.log /results/optimized-build.log \
    /results/baseline-time-{1,2,3}.log /results/optimized-time-{1,2,3}.log \
    /results/summary.txt

echo 'Подготовка инструментов...'
apt-get update
apt-get install -y --no-install-recommends \
    clang-14 time git make g++ cmake python3 ca-certificates

cd /work
userver-create-service --grpc --mongo --postgresql build_check

git clone --depth 1 --branch v1.6.0 \
    https://github.com/aras-p/ClangBuildAnalyzer.git
cmake -S ClangBuildAnalyzer -B ClangBuildAnalyzer/build \
    -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang-14 \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++-14 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build ClangBuildAnalyzer/build -j4
CBA=/work/ClangBuildAnalyzer/build/ClangBuildAnalyzer

cd /work/build_check
cmake -S . -B build -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang-14 \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++-14 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DUSERVER_COMPILATION_TIME_TRACE=ON \
    -DUSERVER_USE_CCACHE=OFF \
    -DCMAKE_C_COMPILER_LAUNCHER= -DCMAKE_CXX_COMPILER_LAUNCHER=

{
    uname -a
    cat /etc/os-release
    cmake --version
    /usr/bin/clang++-14 --version
    "$CBA" --version
} > /results/environment.txt

measure() {
    local name=$1
    echo "$name: сборка для ClangBuildAnalyzer..."
    "$CBA" --start build
    cmake --build build --clean-first -j4 > "/results/$name-build.log" 2>&1
    "$CBA" --stop build "/results/$name.bin"
    "$CBA" --analyze "/results/$name.bin" > "/results/$name.txt"

    for i in 1 2 3; do
        echo "$name: замер времени $i/3..."
        /usr/bin/time -p -o "/results/$name-time-$i.txt" \
            cmake --build build --clean-first -j4 \
            > "/results/$name-time-$i.log" 2>&1
    done
}

measure baseline

sed -i 's|#include <userver/storages/postgres/cluster.hpp>|#include <userver/storages/postgres/postgres_fwd.hpp>|' src/hello_postgres.hpp
sed -i '/#include <hello_postgres.hpp>/a #include <userver/storages/postgres/cluster.hpp>' src/hello_postgres.cpp

measure optimized

for name in baseline optimized; do
    median=$(awk '$1 == "real" {print $2}' /results/"$name"-time-{1,2,3}.txt | sort -n | sed -n '2p')
    echo "$name median: $median seconds"
done > /results/summary.txt
cat /results/summary.txt
