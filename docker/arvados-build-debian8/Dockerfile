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
    && rm -rf /var/lib/apt/lists/*

