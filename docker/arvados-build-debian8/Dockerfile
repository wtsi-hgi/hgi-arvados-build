# arvados-build-debian8
FROM debian:8

ENV DEBIAN_FRONTEND noninteractive

# Install prereqs
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         bash \
         build-essential \
         git \
	 wget \
	 apt-transport-https \
	 ca-certificates \
	 curl \
	 gnupg2 \
	 software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install docker
RUN (curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -) \
    && add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/debian \
    $(lsb_release -cs) \
    stable" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         docker-ce \
    && rm -rf /var/lib/apt/lists/*

# Set DOCKER_HOST for docker client to find docker-dind socket
ENV DOCKER_HOST http:///var/run/docker-dind.sock

# Install dind (docker-in-docker wrapper)
ENV DIND_COMMIT 52379fa76dee07ca038624d639d9e14f4fb719ff
RUN set -ex; \
    wget -O /usr/local/bin/dind "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind"; \
    chmod +x /usr/local/bin/dind

# Setup dockerd (docker-in-docker) to run by default
COPY hgi-arvados-build/dockerd-entrypoint.sh /usr/local/bin/
VOLUME /var/lib/docker
ENTRYPOINT ["dockerd-entrypoint.sh"]
CMD []
