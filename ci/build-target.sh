#!/bin/bash

set -euf -o pipefail

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIRECTORY}/common.sh"

ensureSet CI_PROJECT_DIR

target=$1
echo "build-target.sh: building arvados for ${target}"

echo "build-target.sh: starting docker daemon (logging to /var/log/docker-dind.err)"
nohup dockerd --host=${DOCKER_HOST} --mtu 1400 > /dev/null 2> /var/log/docker-dind.err &
dockerpid=$!
echo "build-target.sh: docker daemon started with pid ${dockerpid}"

# wait for docker.err to log 'acceptconnections() = OK'
docker_ready=""
echo -n "build-target.sh: waiting for docker daemon to be ready."
set +e
while test -z "${docker_ready}"
do
    if ps -p ${dockerpid} > /dev/null
    then
	echo -n "."
	sleep 0.05 || sleep 1
	docker_ready=$(grep 'API listen on /var/run/docker-dind.sock' /var/log/docker-dind.err)
    else
	echo "docker failed!"
	echo "build-target.sh: docker daemon exited, logs are:"
	cat /var/log/docker-dind.err
	exit 1
    fi
done
set -e
echo " docker ready."

echo "build-target.sh: initializing and updating submodules"
git submodule init
git submodule update

export WORKSPACE=${CI_PROJECT_DIR}/submodules/arvados
echo "build-target.sh: using WORKSPACE=${WORKSPACE}"

echo "build-target.sh: calling run-build-packages-one-target.sh --target ${target}"
${WORKSPACE}/build/run-build-packages-one-target.sh --target ${target}

echo "build-target.sh: done!"
exit 0
