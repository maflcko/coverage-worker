#!/bin/bash
set -e
ccache --show-stats

cd /tmp/bitcoin && git pull origin master

if [ "$IS_MASTER" != "true" ]; then
    git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD
    HEAD_COMMIT=$(git rev-parse HEAD)
    if [ "$COMMIT" != "$HEAD_COMMIT" ]; then
        echo "Commit $COMMIT is not equal to HEAD commit $HEAD_COMMIT"
        exit 1
    fi
    
    git rebase master
    S3_COVERAGE_FILE=s3://bitcoin-coverage-data/$PR_NUM/$HEAD_COMMIT/coverage.json
    S3_BENCH_FILE=s3://bitcoin-coverage-data/$PR_NUM/$HEAD_COMMIT/bench.json
else
    git checkout $COMMIT
    S3_COVERAGE_FILE=s3://bitcoin-coverage-data/master/$COMMIT/coverage.json
    S3_BENCH_FILE=s3://bitcoin-coverage-data/master/$COMMIT/bench.json
fi

./test/get_previous_releases.py -b

NPROC_2=$(expr $(nproc) \* 2)

./autogen.sh && ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
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
fi


set +e
bench_exists=$(aws s3 ls $S3_BENCH_FILE)
set -e

if [ "$bench_exists" != "" ]; then
    echo "Bench data already exists for this commit"
else
    BENCH_DURATION=30000
    pyperf system tune || true

    bench_list=$(./src/bench/bench_bitcoin -list)
    time echo "$bench_list" | taskset -c 1-7 parallel --use-cores-instead-of-threads -k --halt now,fail=1 ./src/bench/bench_bitcoin -filter={} -min-time=$BENCH_DURATION -output-json={}-bench.json

    # check that all benchmarks have a medianAbsolutePercentError(elapsed) < 0.01 (1%), otherwise rerun them
    bench_to_rerun=""
    for bench in $bench_list; do
        medianAbsolutePercentError=$(cat $bench-bench.json | jq '.results[0]["medianAbsolutePercentError(elapsed)"]' | sed 's/"//g')
        if (( $(echo "$medianAbsolutePercentError > 0.01" |bc -l) )); then
            echo "Benchmark $bench has a medianAbsolutePercentError(elapsed) of $medianAbsolutePercentError, rerunning"
            bench_to_rerun="$bench_to_rerun $bench"
        fi
    done

    bench_to_rerun=$(echo $bench_to_rerun | tr " " "\n")
    if [ "$bench_to_rerun" != "" ]; then
        time echo "$bench_to_rerun" | taskset -c 1-7 parallel --use-cores-instead-of-threads -k --halt now,fail=1 ./src/bench/bench_bitcoin -filter={} -min-time=$BENCH_DURATION -output-json={}-bench.json
    fi

    # each file outputs {"results": [{...}]}
    # we want to merge all the results into one file
    echo '{"results": [' > bench.json
    for bench in $bench_list; do
        cat $bench-bench.json | jq '.results[0]' >> bench.json
        echo "," >> bench.json
    done
    # remove last comma
    sed -i '$ s/.$//' bench.json
    echo "]}" >> bench.json

    aws s3 cp bench.json $S3_BENCH_FILE

    pyperf system reset || true
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
