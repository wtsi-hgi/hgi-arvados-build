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

# Install docker client
RUN (curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -) \
    && add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/debian \
    $(lsb_release -cs) \
    stable" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         docker-ce \
    && rm -rf /var/lib/apt/lists/*
