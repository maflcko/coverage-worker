#!/bin/bash
set -e

git clone https://github.com/bitcoin/bitcoin.git /tmp/bitcoin
cd /tmp/bitcoin
git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD

# check depends folder exists in gcloud bucket 'bitcoin-coverage-cache'
if aws s3 ls s3://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu/; then
    echo "Found cached depends folder"
    aws s3 cp --recursive s3://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu /tmp/bitcoin/depends
else
    echo "No cached depends folder found"
    CC=clang CXX=clang++ make -C depends NO_BOOST=1 NO_LIBEVENT=1 NO_QT=1 NO_SQLITE=1 NO_NATPMP=1 NO_UPNP=1 NO_ZMQ=1 NO_USDT=1
    aws s3 cp --recursive /tmp/bitcoin/depends/x86_64-pc-linux-gnu s3://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu
fi

BDB_PREFIX="/tmp/bitcoin/depends/x86_64-pc-linux-gnu"

mkdir -p /tmp/bitcoin/releases
aws s3 cp --recursive s3://bitcoin-coverage-cache/releases /tmp/bitcoin/releases || echo "No cached previous releases found"
./test/get_previous_releases.py -b
for f in /tmp/bitcoin/releases/*; do
    if ! aws s3 ls s3://bitcoin-coverage-cache/releases/$(basename $f)/; then
        echo "Uploading $(basename $f) to gcloud bucket"
        aws s3 cp --recursive $f s3://bitcoin-coverage-cache/releases/$(basename $f)
    else
        echo "Found cached $(basename $f)"
    fi
done
# set chmod +x to releases/**/bin/*
find /tmp/bitcoin/releases -type f -exec chmod +x {} \;

sed -i "s|functional/test_runner.py |functional/test_runner.py --previous-releases --timeout-factor=10 --exclude=feature_dbcrash -j$(nproc) |g" ./Makefile.am && \
    sed -i 's|$(LCOV) -z $(LCOV_OPTS) -d $(abs_builddir)/src||g' ./Makefile.am

./autogen.sh && CXX=clang++ CC=clang ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq --disable-bench BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
bear -- make -j$(nproc)
make cov

gcovr --json --gcov-executable "llvm-cov gcov" --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb > coverage.json
aws s3 cp coverage.json s3://bitcoin-coverage-data/$PR_NUM/coverage.json


changed_files=$(git --no-pager diff --name-only FETCH_HEAD $(git merge-base FETCH_HEAD master))
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

parallel --jobs $(nproc) < commands.txt
sed -i 's|/tmp/bitcoin/||g' /tmp/mutations/*.yml

cd /tmp/mutations && zip -r /tmp/mutations.zip *

aws s3 cp /tmp/mutations.zip s3://bitcoin-coverage-data/$PR_NUM/mutations.zip
