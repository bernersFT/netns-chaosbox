
FROM debian:12-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        wget \
        libreadline-dev \
        libssl-dev \
        zlib1g-dev \
        libncurses-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local

RUN wget -O softether.tar.gz \
  https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.44-9807-rtm/softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz

RUN ls -lh softether.tar.gz && \
    tar xzf softether.tar.gz && \
    rm softether.tar.gz

WORKDIR /usr/local/vpnserver

RUN printf "1\n1\n" | make && \
    chmod 600 * && \
    chmod 700 vpnserver vpncmd


FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -o Acquire::ForceIPv4=true && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        iproute2 \
        iptables \
        iputils-ping && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/vpnserver

COPY --from=build /usr/local/vpnserver /usr/local/vpnserver

VOLUME ["/usr/local/vpnserver"]

EXPOSE 443/tcp 992/tcp 1194/tcp 1194/udp 5555/tcp

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["execsvc"]