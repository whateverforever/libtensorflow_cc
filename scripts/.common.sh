# ==============================================================================
# MIT License
# Copyright 2022 Institute for Automotive Engineering of RWTH Aachen University.
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================

set -e
set -o pipefail

DEFAULT_TF_VERSION="2.13.0"
DEFAULT_TF_VERSION_NOBLE="2.18.0"
DEFAULT_JOBS=$(nproc 2> /dev/null || sysctl -n hw.ncpu)
DEFAULT_GPU=1
DEFAULT_ARCH=$(dpkg --print-architecture 2> /dev/null || uname -m)
DEFAULT_UBUNTU_CODENAME="focal"
DEFAULT_PYTHON_VERSION="3.12"

TF_VERSION=${TF_VERSION:-${DEFAULT_TF_VERSION}}
JOBS=${JOBS:-${DEFAULT_JOBS}}
GPU=${GPU:-${DEFAULT_GPU}}
[[ $GPU == "1" ]] && GPU_POSTFIX="-gpu" || GPU_POSTFIX=""
ARCH=${ARCH:-${DEFAULT_ARCH}}
UBUNTU_CODENAME=${UBUNTU_CODENAME:-${DEFAULT_UBUNTU_CODENAME}}
PYTHON_VERSION=${PYTHON_VERSION:-${DEFAULT_PYTHON_VERSION}}

TF_VERSION_MAJOR=$(echo ${TF_VERSION} | cut -d. -f1)
TF_VERSION_MINOR=$(echo ${TF_VERSION} | cut -d. -f2)
# TF >= 2.16 ships only the SIG Build dockerfiles; the public *-devel tags
# at tensorflow/tensorflow are deprecated and the replacement is tensorflow/build.
USE_SIG_BUILD=$(awk "BEGIN {print (($TF_VERSION_MAJOR > 2) || ($TF_VERSION_MAJOR == 2 && $TF_VERSION_MINOR >= 16)) ? 1 : 0}")

if [ "$ARCH" = "arm64" ]; then
    DEFAULT_TF_CUDA_COMPUTE_CAPABILITIES=5.3,6.2,7.2,8.7
else
    DEFAULT_TF_CUDA_COMPUTE_CAPABILITIES=6.0,6.1,7.0,7.5,8.0,8.6,8.9,9.0
fi
TF_CUDA_COMPUTE_CAPABILITIES=${TF_CUDA_COMPUTE_CAPABILITIES:-${DEFAULT_TF_CUDA_COMPUTE_CAPABILITIES}}

# build stage base image:
#   TF <  2.16: tensorflow/tensorflow:${TF_VERSION}-devel${GPU_POSTFIX}-${ARCH}
#   TF >= 2.16: tensorflow/build:${MAJOR}.${MINOR}-python${PYTHON_VERSION}
if [ "$USE_SIG_BUILD" = "1" ]; then
    DEFAULT_DEVEL_IMAGE="tensorflow/build:${TF_VERSION_MAJOR}.${TF_VERSION_MINOR}-python${PYTHON_VERSION}"
else
    DEFAULT_DEVEL_IMAGE="tensorflow/tensorflow:${TF_VERSION}-devel${GPU_POSTFIX}-${ARCH}"
fi
DEVEL_IMAGE=${DEVEL_IMAGE:-${DEFAULT_DEVEL_IMAGE}}

# final stage base image for amd64: use the TF runtime image on focal, plain ubuntu on noble
if [ "${UBUNTU_CODENAME}" = "noble" ]; then
    DEFAULT_FINAL_BASE_AMD64="ubuntu:noble"
else
    DEFAULT_FINAL_BASE_AMD64="tensorflow/tensorflow:${TF_VERSION}${GPU_POSTFIX}"
fi
FINAL_BASE_AMD64=${FINAL_BASE_AMD64:-${DEFAULT_FINAL_BASE_AMD64}}

UBUNTU_CODENAME_SUFFIX=$([[ "${UBUNTU_CODENAME}" != "focal" ]] && echo "-${UBUNTU_CODENAME}" || echo "")

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(realpath $(dirname "$0"))
REPOSITORY_DIR=$(realpath ${SCRIPT_DIR}/..)
DOCKER_DIR=${REPOSITORY_DIR}/docker
LOG_DIR=${DOCKER_DIR}/.log
LOG_FILE=${LOG_DIR}/${SCRIPT_NAME}_${TF_VERSION}${GPU_POSTFIX}${UBUNTU_CODENAME_SUFFIX}.log
mkdir -p ${LOG_DIR}

DOWNLOAD_DOCKERFILES_DIR=${DOCKER_DIR}/.Dockerfiles
DOWNLOAD_DOCKERFILE_DIR=${DOWNLOAD_DOCKERFILES_DIR}/${TF_VERSION}

IMAGE_DEVEL_ARCH="${DEVEL_IMAGE}"
IMAGE_CPP="rwthika/tensorflow-cc:${TF_VERSION}${GPU_POSTFIX}${UBUNTU_CODENAME_SUFFIX}"
IMAGE_CPP_ARCH="${IMAGE_CPP}-${ARCH}"
IMAGE_LIBTENSORFLOW_CC_ARCH="rwthika/tensorflow-cc:${TF_VERSION}-libtensorflow_cc${GPU_POSTFIX}${UBUNTU_CODENAME_SUFFIX}-${ARCH}"
