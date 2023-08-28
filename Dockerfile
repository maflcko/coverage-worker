FROM ubuntu:22.04

# run curl healthcheck every 5 seconds
HEALTHCHECK --interval=5s --timeout=3s CMD curl -X POST ${HEALTHCHECK_WEBHOOK} -H "Content-Type: application/json" -d '{"text":"Bitcoin coverage build is running"}' || exit 1

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y git python3-zmq libevent-dev libboost-dev libdb5.3++-dev libsqlite3-dev libminiupnpc-dev libzmq3-dev lcov libtool autotools-dev automake pkg-config bsdmainutils bsdextrautils curl wget python3-pip lsb-release software-properties-common gnupg unzip bear
RUN pip install gcovr
RUN wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 16
RUN apt install -y clang-tidy-16 clang-format-16 clang-16
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100
RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100
RUN update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-16 100
RUN update-alternatives --install /usr/bin/llvm-cov llvm-cov /usr/bin/llvm-cov-16 100
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN apt update && apt install google-cloud-cli -y

RUN git config --global user.email "bitcoin-coverage@aureleoules.com"
RUN git config --global user.name "bitcoin-coverage"

RUN wget https://nightly.link/bitcoin-coverage/clang-tidy-mutators/workflows/cmake-single-platform/master/libbitcoin-mutator.so.zip?h=1b1a87b8efa5f7fc36e228bb8e3ec95dea0d8529 -O libbitcoin-mutator.so.zip && \
    unzip libbitcoin-mutator.so.zip && \
    mv libbitcoin-mutator.so /usr/lib/ && \
    rm -rf libbitcoin-mutator.so.zip

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]