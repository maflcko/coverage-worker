#!/bin/sh

gcloud auth activate-service-account --key-file=/key.json

git clone https://github.com/bitcoin/bitcoin.git /tmp/bitcoin
cd /tmp/bitcoin
git fetch origin pull/$PR_NUM/head && git checkout FETCH_HEAD

make -C depends NO_BOOST=1 NO_LIBEVENT=1 NO_QT=1 NO_SQLITE=1 NO_NATPMP=1 NO_UPNP=1 NO_ZMQ=1 NO_USDT=1
BDB_PREFIX="/tmp/bitcoin/depends/x86_64-pc-linux-gnu"
./test/get_previous_releases.py -b
sed -i "s|functional/test_runner.py |functional/test_runner.py --previous-releases --timeout-factor=10 --exclude=feature_dbcrash -j$(nproc) |g" ./Makefile.am && \
    sed -i 's|$(LCOV) -z $(LCOV_OPTS) -d $(abs_builddir)/src||g' ./Makefile.am

./autogen.sh && ./configure --disable-fuzz --enable-fuzz-binary=no --with-gui=no --disable-zmq --disable-bench BDB_LIBS="-L${BDB_PREFIX}/lib -ldb_cxx-4.8" BDB_CFLAGS="-I${BDB_PREFIX}/include" --enable-lcov #--enable-extended-functional-tests
make -j$(nproc)
make cov

gcovr --json --gcov-ignore-parse-errors -e depends -e src/test -e src/leveldb > coverage.json
gsutil cp coverage.json gs://bitcoin-coverage-data/$PR_NUM/coverage.json

codecov -P $PR_NUM