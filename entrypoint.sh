#!/bin/bash
set -e

cd /tmp/bitcoin && git pull origin master
git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD
./test/get_previous_releases.py -b

sed -i "s|functional/test_runner.py |functional/test_runner.py --previous-releases --timeout-factor=10 --exclude=feature_dbcrash -j$(nproc) |g" ./Makefile.am && \
    sed -i 's|$(LCOV) -z $(LCOV_OPTS) -d $(abs_builddir)/src||g' ./Makefile.am

./autogen.sh && CXX=clang++ CC=clang ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq --disable-bench BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
bear -- make -j$(nproc)
make cov

gcovr --json --gcov-executable "llvm-cov gcov" --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb > coverage.json
aws s3 cp coverage.json s3://bitcoin-coverage-data/$PR_NUM/coverage.json

changed_files=$(git --no-pager diff --name-only FETCH_HEAD $(git merge-base FETCH_HEAD master))

if [ -n "$changed_files" ]; then
    changed_files=$(echo "$changed_files" | grep -E "^src/")
    changed_files=$(echo "$changed_files" | grep -vE "^src/(test|wallet/test)/")
    changed_files=$(echo "$changed_files" | grep -E "\.(cpp|h)$")
    changed_files=$(echo "$changed_files" | tr '\n' ' ')
    changed_files=$(echo "$changed_files" | sed 's/ $//g')
    # remove src/ from each file
    changed_files_base=$(echo "$changed_files" | sed 's/src\///g')

    # for each file create an array of object like [{"name": "spend.cpp"}, {"name": ...]
    filter="[{\"name\": \"$(echo "$changed_files_base" | sed 's| |\"}, {\"name\": \"|g')\"}]"

    mutators=$(clang-tidy -load /usr/lib/libbitcoin-mutator.so --list-checks --checks=mutator-* | grep "mutator-")

    mkdir /tmp/mutations
    for mutator in $mutators; do
        echo "clang-tidy -load /usr/lib/libbitcoin-mutator.so --checks=$mutator --line-filter='$filter' --export-fixes=/tmp/mutations/$mutator.yml $changed_files" >> commands.txt
    done

    parallel --jobs $(nproc) < commands.txt || true
    sed -i 's|/tmp/bitcoin/||g' /tmp/mutations/*.yml

    cd /tmp/mutations && zip -r /tmp/mutations.zip *

    aws s3 cp /tmp/mutations.zip s3://bitcoin-coverage-data/$PR_NUM/mutations.zip
fi