#!/bin/bash
set -e

err() {
    echo "Error occurred:"
    awk 'NR>L-4 && NR<L+4 { printf "%-5d%3s%s\n",NR,(NR==L?">>>":""),$0 }' L=$1 $0
}
trap 'err $LINENO' ERR

# if /key.json exists
if [ -f /key.json ]; then
    echo "Found key.json"
    gcloud auth activate-service-account --key-file /key.json
else
    gcloud config set account $GCP_ACCOUNT
fi

git clone https://github.com/bitcoin/bitcoin.git /tmp/bitcoin
cd /tmp/bitcoin
git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD

# check depends folder exists in gcloud bucket 'bitcoin-coverage-cache'
if gsutil -q stat gs://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu/; then
    echo "Found cached depends folder"
    gsutil -m cp -r gs://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu /tmp/bitcoin/depends
else
    echo "No cached depends folder found"
    make -C depends NO_BOOST=1 NO_LIBEVENT=1 NO_QT=1 NO_SQLITE=1 NO_NATPMP=1 NO_UPNP=1 NO_ZMQ=1 NO_USDT=1
    gsutil -m cp -r /tmp/bitcoin/depends/x86_64-pc-linux-gnu gs://bitcoin-coverage-cache/depends/x86_64-pc-linux-gnu
fi

BDB_PREFIX="/tmp/bitcoin/depends/x86_64-pc-linux-gnu"

mkdir -p /tmp/bitcoin/releases
gsutil -m cp -r gs://bitcoin-coverage-cache/releases /tmp/bitcoin || echo "No cached previous releases found"
./test/get_previous_releases.py -b
for f in /tmp/bitcoin/releases/*; do
    if ! gsutil -m ls gs://bitcoin-coverage-cache/releases/$(basename $f)/; then
        echo "Uploading $(basename $f) to gcloud bucket"
        gsutil -m cp -r $f gs://bitcoin-coverage-cache/releases
    else
        echo "Found cached $(basename $f)"
    fi
done

sed -i "s|functional/test_runner.py |functional/test_runner.py --previous-releases --timeout-factor=10 --exclude=feature_dbcrash -j$(nproc) |g" ./Makefile.am && \
    sed -i 's|$(LCOV) -z $(LCOV_OPTS) -d $(abs_builddir)/src||g' ./Makefile.am

./autogen.sh && ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq --disable-bench BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
make -j$(nproc)
make cov

gcovr --json --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb > coverage.json
gsutil cp coverage.json gs://bitcoin-coverage-data/$PR_NUM/coverage.json
