#!/bin/bash
set -e
ccache --show-stats

cd /tmp/bitcoin && git pull origin master
MASTER_COMMIT=$(git rev-parse HEAD)

if [ "$IS_MASTER" != "true" ]; then
    git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD
    HEAD_COMMIT=$(git rev-parse HEAD)
    if [ "$COMMIT" != "$HEAD_COMMIT" ]; then
        echo "Commit $COMMIT is not equal to HEAD commit $HEAD_COMMIT"
        exit 1
    fi
    
    git rebase master
    S3_COVERAGE_FILE=s3://$S3_BUCKET_DATA/$PR_NUM/$HEAD_COMMIT/coverage.json
    S3_BENCH_FILE=s3://$S3_BUCKET_ARTIFACTS/$PR_NUM/$HEAD_COMMIT/bench_bitcoin
else
    git checkout $COMMIT
    S3_COVERAGE_FILE=s3://$S3_BUCKET_DATA/master/$COMMIT/coverage.json
    S3_BENCH_FILE=s3://$S3_BUCKET_ARTIFACTS/master/$COMMIT/bench_bitcoin
fi

./test/get_previous_releases.py -b

NPROC_2=$(expr $(nproc) \* 2)

./autogen.sh && ./configure --disable-bench --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
time compiledb make -j$(nproc)

set +e
coverage_exists=$(aws s3 ls $S3_COVERAGE_FILE)
set -e

if [ "$coverage_exists" != "" ]; then
    echo "Coverage data already exists for this commit"
else
    time ./src/test/test_bitcoin --list_content 2>&1 | grep -v "    " | parallel --halt now,fail=1 ./src/test/test_bitcoin -t {} 2>&1
    time python3 test/functional/test_runner.py -F --previous-releases --timeout-factor=10 --exclude=feature_reindex_readonly,feature_dbcrash -j$NPROC_2

    time gcovr --json --gcov-ignore-errors=no_working_dir_found --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb -e src/bench -e src/qt -j $(nproc) > coverage.json

    aws s3 cp coverage.json $S3_COVERAGE_FILE
    if [ "$IS_MASTER" != "true" ]; then
        echo $MASTER_COMMIT > .base_commit
        aws s3 cp .base_commit s3://$S3_BUCKET_DATA/$PR_NUM/$HEAD_COMMIT/.base_commit
    fi
fi

set +e
bench_exists=$(aws s3 ls $S3_BENCH_FILE)
set -e

if [ "$bench_exists" != "" ]; then
    echo "Bench binary already exists for this commit"
else
    ./configure --enable-bench --disable-tests --disable-gui --disable-zmq --disable-fuzz --enable-fuzz-binary=no BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include"
    make clean
    time make -j$(nproc)
    aws s3 cp src/bench/bench_bitcoin $S3_BENCH_FILE
fi

# if [ "$IS_MASTER" != "true" ]; then
#     echo "Updating $PR_NUM branch on sonarcloud"
#     time /usr/lib/sonar-scanner/bin/sonar-scanner \
#     -Dsonar.organization=aureleoules \
#     -Dsonar.projectKey=aureleoules_bitcoin \
#     -Dsonar.sources=. \
#     -Dsonar.cfamily.compile-commands=compile_commands.json \
#     -Dsonar.host.url=https://sonarcloud.io \
#     -Dsonar.exclusions='src/crc32c/**, src/crypto/ctaes/**, src/leveldb/**, src/minisketch/**, src/secp256k1/**, src/univalue/**' \
#     -Dsonar.cfamily.threads=$(nproc) \
#     -Dsonar.branch.name=$PR_NUM \
#     -Dsonar.cfamily.analysisCache.mode=server \
#     -Dsonar.branch.target=master
# else
#     echo "Updating master branch on sonarcloud"
#     time /usr/lib/sonar-scanner/bin/sonar-scanner \
#     -Dsonar.organization=aureleoules \
#     -Dsonar.projectKey=aureleoules_bitcoin \
#     -Dsonar.sources=. \
#     -Dsonar.cfamily.compile-commands=compile_commands.json \
#     -Dsonar.host.url=https://sonarcloud.io \
#     -Dsonar.exclusions='src/crc32c/**, src/crypto/ctaes/**, src/leveldb/**, src/minisketch/**, src/secp256k1/**, src/univalue/**' \
#     -Dsonar.cfamily.threads=$(nproc) \
#     -Dsonar.branch.name=master \
#     -Dsonar.cfamily.analysisCache.mode=server
# fi
