#!/bin/sh

nohup dockerd --host=${DOCKER_HOST} > /dev/null 2> /var/log/docker-dind.err &
dockerpid=$!

# wait for docker.err to log 'acceptconnections() = OK'
docker_ready=""
echo -n "Waiting for docker daemon to be ready."
while test -z "${docker_ready}"
do
    # docker hasn't reported that it is ready yet, check if it has exited
    grep -q exit /var/log/docker-dind.err && echo "docker daemon has exited!" && echo "docker log:" && cat /var/log/docker-dind.err && exit 1

    echo -n "."
    sleep 0.05 || sleep 1
    docker_ready=$(grep 'API listen on /var/run/docker-dind.sock' /var/log/docker-dind.err)
done
echo " docker ready."

exec "$@"
