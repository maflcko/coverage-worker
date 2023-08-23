FROM debian:bullseye

# run curl healthcheck every 5 seconds
HEALTHCHECK --interval=5s --timeout=3s CMD curl ${HEALTHCHECK_URL} || exit 1

ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/cache/ccache
RUN apt update && apt install -y git python3-zmq libevent-dev libboost-dev libdb5.3++-dev libsqlite3-dev libminiupnpc-dev libzmq3-dev lcov build-essential libtool autotools-dev automake pkg-config bsdmainutils bsdextrautils clang llvm curl wget python3-pip
RUN pip install gcovr
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN apt update && apt install google-cloud-cli -y

RUN git config --global user.email "bitcoin-coverage@aureleoules.com"
RUN git config --global user.name "bitcoin-coverage"

RUN wget https://github.com/mozilla/sccache/releases/download/v0.5.4/sccache-v0.5.4-x86_64-unknown-linux-musl.tar.gz && \
    tar -xvf sccache-v0.5.4-x86_64-unknown-linux-musl.tar.gz && \
    mv sccache-v0.5.4-x86_64-unknown-linux-musl/sccache /usr/bin/sccache && \
    chmod +x /usr/bin/sccache && \
    rm -rf sccache-v0.5.4-x86_64-unknown-linux-musl.tar.gz sccache-v0.5.4-x86_64-unknown-linux-musl

RUN ln -s /usr/bin/sccache /usr/bin/ccache

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]