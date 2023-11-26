#!/bin/bash
set -e
ccache --show-stats

cd /tmp/bitcoin && git pull origin master
git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD
HEAD_COMMIT=$(git rev-parse HEAD)
git rebase master
./test/get_previous_releases.py -b

NPROC_2=$(expr $(nproc) \* 2)
echo "NPROC_2=$NPROC_2"
sed -i "s|functional/test_runner.py |functional/test_runner.py -F --previous-releases --timeout-factor=10 --exclude=feature_reindex_readonly,feature_dbcrash -j$NPROC_2 |g" ./Makefile.am
sed -i 's|$(MAKE) -C src/ check|./src/test/test_bitcoin --list_content 2>\&1 \| grep -v "    " \| parallel --halt now,fail=1 ./src/test/test_bitcoin -t {} 2>\&1|g' ./Makefile.am
sed -i 's|$(LCOV) -z $(LCOV_OPTS) -d $(abs_builddir)/src||g' ./Makefile.am

# create function 
function configure_and_compile() {
    ./autogen.sh && ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
    compiledb make -j$(nproc)
}

configure_and_compile
make cov

gcovr --json --gcov-ignore-errors=no_working_dir_found --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb -e src/bench -e src/qt > coverage.json
aws s3 cp coverage.json s3://bitcoin-coverage-data/$PR_NUM/$HEAD_COMMIT/coverage.json

modprobe msr
pyperf system tune
./src/bench/bench_bitcoin -output-json=bench.json -min-time=1000
aws s3 cp bench.json s3://bitcoin-coverage-data/$PR_NUM/$HEAD_COMMIT/bench.json
pyperf system reset

last_master_commit=$(curl "https://sonarcloud.io/api/project_analyses/search?project=aureleoules_bitcoin&branch=master" | jq -r '.analyses[0].revision')
# check if the last master commit is the same as the current master commit
checked_master=0
if [ "$last_master_commit" != "$(git rev-parse master)" ]; then
    git stash && git checkout master
    make clean
    configure_and_compile
    # If it is not, we need to update the master branch on sonarcloud
    echo "Updating master branch on sonarcloud"
    /usr/lib/sonar-scanner/bin/sonar-scanner \
        -Dsonar.organization=aureleoules \
        -Dsonar.projectKey=aureleoules_bitcoin \
        -Dsonar.sources=. \
        -Dsonar.cfamily.compile-commands=compile_commands.json \
        -Dsonar.host.url=https://sonarcloud.io \
        -Dsonar.exclusions='src/crc32c/**, src/crypto/ctaes/**, src/leveldb/**, src/minisketch/**, src/secp256k1/**, src/univalue/**' \
        -Dsonar.cfamily.analysisCache.mode=server \
        -Dsonar.cfamily.threads=$(nproc)

    git checkout FETCH_HEAD

    checked_master=1
fi

if [ "$checked_master" -eq 1 ]; then
    make clean
    configure_and_compile
fi

echo "Updating $PR_NUM branch on sonarcloud"
/usr/lib/sonar-scanner/bin/sonar-scanner \
    -Dsonar.organization=aureleoules \
    -Dsonar.projectKey=aureleoules_bitcoin \
    -Dsonar.sources=. \
    -Dsonar.cfamily.compile-commands=compile_commands.json \
    -Dsonar.host.url=https://sonarcloud.io \
    -Dsonar.exclusions='src/crc32c/**, src/crypto/ctaes/**, src/leveldb/**, src/minisketch/**, src/secp256k1/**, src/univalue/**' \
    -Dsonar.cfamily.threads=$(nproc) \
    -Dsonar.branch.name=$PR_NUM \
    -Dsonar.cfamily.analysisCache.mode=server \
    -Dsonar.branch.target=master
