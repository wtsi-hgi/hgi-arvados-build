#!/bin/bash

set -euf -o pipefail

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIRECTORY}/common.sh"

ensureSet CI_PROJECT_DIR

target=$1
echo "build-target.sh: building arvados for ${target}"

export WORKSPACE=${CI_PROJECT_DIR}/subrepos/arvados
echo "build-target.sh: using WORKSPACE=${WORKSPACE}"

echo "build-target.sh: calling run-build-packages-one-target.sh --target ${target}"
${WORKSPACE}/build/run-build-packages-one-target.sh --target ${target}

echo "build-target.sh: done!"
exit 0
