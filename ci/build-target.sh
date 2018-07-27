#!/bin/bash

set -euf -o pipefail

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIRECTORY}/common.sh"

ensureSet CI_PROJECT_DIR

export WORKSPACE=${CI_PROJECT_DIR}/subrepos/arvados
${CI_PROJECT_DIR}/subrepos/arvados/build/run-build-packages-one-target.sh $1
