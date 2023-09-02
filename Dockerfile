FROM ubuntu:22.04

# run curl healthcheck every 5 seconds
HEALTHCHECK --interval=5s --timeout=3s CMD curl -X POST ${HEALTHCHECK_WEBHOOK} -H "Content-Type: application/json" -d '{"text":"Bitcoin coverage build is running"}' || exit 1

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y git python3-zmq libevent-dev libboost-dev libdb5.3++-dev libsqlite3-dev libminiupnpc-dev libzmq3-dev lcov libtool autotools-dev automake pkg-config bsdmainutils bsdextrautils curl wget python3-pip lsb-release software-properties-common gnupg unzip bear jq parallel zip
RUN pip install gcovr
RUN wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 16
RUN apt install -y clang-tidy-16 clang-16
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100
RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100
RUN update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-16 100
RUN update-alternatives --install /usr/bin/llvm-cov llvm-cov /usr/bin/llvm-cov-16 100
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

RUN git config --global user.email "bitcoin-coverage@aureleoules.com"
RUN git config --global user.name "bitcoin-coverage"

RUN wget https://nightly.link/bitcoin-coverage/chernobyl/workflows/cmake-single-platform/master/libbitcoin-mutator.so.zip?h=c25bdfbe7b86210a96437322d9633c6003aebba5 -O libbitcoin-mutator.so.zip && \
    unzip libbitcoin-mutator.so.zip && \
    mv libbitcoin-mutator.so /usr/lib/ && \
    rm -rf libbitcoin-mutator.so.zip

RUN git clone https://github.com/bitcoin/bitcoin.git /tmp/bitcoin
WORKDIR /tmp/bitcoin
RUN CC=clang CXX=clang++ make -C depends NO_BOOST=1 NO_LIBEVENT=1 NO_QT=1 NO_SQLITE=1 NO_NATPMP=1 NO_UPNP=1 NO_ZMQ=1 NO_USDT=1
ENV BDB_PREFIX=/tmp/bitcoin/depends/x86_64-pc-linux-gnu
RUN mkdir -p /tmp/bitcoin/releases && ./test/get_previous_releases.py -b

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]