#!/bin/sh
set -e

nohup dockerd --host=${DOCKER_HOST} > /var/log/docker.out 2> /var/log/docker.err &
dockerpid=$!

# wait for docker.err to log 'acceptconnections() = OK'
docker_ready=""
echo -n "Waiting for docker daemon to be ready."
while test -z "${docker_ready}"
do
    # docker hasn't reported that it is ready yet, check if it has exited
    grep -q exit /var/log/docker.err && echo " docker daemon has exited!" && echo "docker log:" && cat /var/log/docker.err && exit 1

    echo -n "."
    sleep 0.05 || sleep 1
    docker_ready=$(grep 'acceptconnections.*=.*OK' /var/log/docker.err)
done
echo " docker ready."

exec "$@"
