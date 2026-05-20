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

# --- build stage for building libtensorflow_cc --------------------------------
ARG TARGETARCH
ARG TF_VERSION=master
ARG GPU_POSTFIX=-gpu
ARG UBUNTU_CODENAME=focal
# Overridable base image for the build stage. Scripts compute this based on
# TF_VERSION: tensorflow/tensorflow:*-devel* for TF < 2.16, tensorflow/build:*
# (SIG Build) for TF >= 2.16, because the public *-devel tags were deprecated.
# Required: scripts/.common.sh always passes this. Direct docker builds must too.
ARG DEVEL_IMAGE
# Overridable base image for the amd64 final stage.
# Defaults to ubuntu:focal; scripts set this to the TF runtime image on focal
# or ubuntu:noble on noble.
ARG FINAL_BASE_AMD64=ubuntu:focal
FROM ${DEVEL_IMAGE} as build

ARG TARGETARCH
ARG TF_VERSION
ARG GPU_POSTFIX

# clone TensorFlow
RUN git clone --branch v${TF_VERSION} --depth=1 https://github.com/tensorflow/tensorflow.git /tensorflow
WORKDIR /tensorflow

# fix build issue in 2.10.0, 2.10.1
# https://github.com/tensorflow/tensorflow/issues/57826
RUN if [ "${TF_VERSION}" = "2.10.0" ] || [ "${TF_VERSION}" = "2.10.1" ]; then \
        git fetch --depth=1 origin b1bd1d6beeac169ce669f81dcbf3c48899ca1ed0 && \
        git checkout FETCH_HEAD -- tensorflow/BUILD; \
    fi

# fix GPU-version build issue in 2.11.1, 2.12.0, 2.12.1, 2.13.0
# https://github.com/tensorflow/tensorflow/issues/60398#issuecomment-1537040602
COPY patch/ patch/
RUN if [ "${TF_VERSION}" = "2.11.1" ] || [ "${TF_VERSION}" = "2.12.0" ] || [ "${TF_VERSION}" = "2.12.1" ] || [ "${TF_VERSION}" = "2.13.0" ]; then \
        git apply patch/${TF_VERSION}/workspace2.bzl.patch; \
    fi

# configure compilation
ENV PYTHON_BIN_PATH=/usr/bin/python3
ENV PYTHON_LIB_PATH=/usr/lib/python3/dist-packages
ENV TF_NEED_ROCM=0
ARG TF_CUDA_COMPUTE_CAPABILITIES=6.0,6.1,7.0,7.5,8.0,8.6,8.9,9.0
ENV TF_CUDA_COMPUTE_CAPABILITIES=${TF_CUDA_COMPUTE_CAPABILITIES}
ENV GCC_HOST_COMPILER_PATH=/usr/bin/gcc
ENV CC_OPT_FLAGS="-march=native -Wno-sign-compare"
ENV TF_SET_ANDROID_WORKSPACE=0
# TF_CUDA_CLANG selects the CUDA crosstool flavor at ./configure time:
#   0 -> nvcc + crosstool_wrapper_driver_is_not_gcc (older TF, devel images)
#   1 -> clang as the CUDA driver, no wrapper        (SIG Build, TF >= 2.16)
# The SIG Build image (TF >= 2.16) ships clang-18 at /usr/lib/llvm-18; --config=cuda
# expects a clang-direct crosstool there, otherwise bazel emits wrapper-style flags
# (-nvcc_options=, -Xcuda-fatbinary=) that the plain clang driver does not accept.
RUN TF_MINOR=$(echo ${TF_VERSION} | cut -d. -f2) && \
    TF_MAJOR=$(echo ${TF_VERSION} | cut -d. -f1) && \
    USE_SIG_BUILD=$(awk "BEGIN {print (($TF_MAJOR > 2) || ($TF_MAJOR == 2 && $TF_MINOR >= 16)) ? 1 : 0}") && \
    if [ "$USE_SIG_BUILD" = "1" ]; then \
        export TF_CUDA_CLANG=1 CLANG_CUDA_COMPILER_PATH=/usr/lib/llvm-18/bin/clang ; \
    else \
        export TF_CUDA_CLANG=0 ; \
    fi && \
    ./configure

# build C++ library
# TF >= 2.10 must be built non-monolithic due to runtime issue
# https://github.com/tensorflow/tensorflow/issues/59081
# For TF >= 2.16 (SIG Build), GPU builds use --config=cuda, which routes device
# code through hermetic clang-18.  --config=nvcc_clang is intentionally avoided:
# it routes device code through nvcc, which lacks clang-specific NVVM intrinsics
# (e.g. __nvvm_read_ptx_sreg_laneid) used in TF's gpu_device_functions.h.
ARG JOBS="auto"
RUN TF_MINOR=$(echo ${TF_VERSION} | cut -d. -f2) && \
    TF_MAJOR=$(echo ${TF_VERSION} | cut -d. -f1) && \
    NON_MONO=$(awk "BEGIN {print (($TF_MAJOR > 2) || ($TF_MAJOR == 2 && $TF_MINOR >= 10)) ? 1 : 0}") && \
    USE_SIG_BUILD=$(awk "BEGIN {print (($TF_MAJOR > 2) || ($TF_MAJOR == 2 && $TF_MINOR >= 16)) ? 1 : 0}") && \
    CUDA_CONFIG="cuda" && \
    EXTRA_COPTS=$([ "$USE_SIG_BUILD" = "1" ] && echo "--copt=-Wno-error=unused-command-line-argument --host_copt=-Wno-error=unused-command-line-argument --copt=-Wno-error=gnu-offsetof-extensions --host_copt=-Wno-error=gnu-offsetof-extensions" || echo "") && \
    if [ "${GPU_POSTFIX}" = "-gpu" ]; then \
        if [ "$NON_MONO" = "1" ]; then \
            bazel build --jobs ${JOBS} --config=${CUDA_CONFIG} --config=opt ${EXTRA_COPTS} --verbose_failures tensorflow:libtensorflow_cc.so tensorflow:install_headers; \
        else \
            bazel build --jobs ${JOBS} --config=${CUDA_CONFIG} --config=opt --config=monolithic ${EXTRA_COPTS} --verbose_failures tensorflow:libtensorflow_cc.so tensorflow:install_headers; \
        fi; \
    else \
        if [ "$NON_MONO" = "1" ]; then \
            bazel build --jobs ${JOBS} --config=opt ${EXTRA_COPTS} --verbose_failures tensorflow:libtensorflow_cc.so tensorflow:install_headers; \
        else \
            bazel build --jobs ${JOBS} --config=opt --config=monolithic ${EXTRA_COPTS} --verbose_failures tensorflow:libtensorflow_cc.so tensorflow:install_headers; \
        fi; \
    fi

# move libtensorflow_cc to separate folder for easier Dockerfile COPY
RUN mkdir -p bazel-bin/tensorflow/lib && \
    mv bazel-bin/tensorflow/libtensorflow_cc.so* bazel-bin/tensorflow/lib/ && \
    mv bazel-bin/tensorflow/libtensorflow_framework.so* bazel-bin/tensorflow/lib/ && \
    ln -sf libtensorflow_framework.so.2 bazel-bin/tensorflow/lib/libtensorflow_framework.so && \
    rm bazel-bin/tensorflow/lib/*params

# build pip package
# TF >= 2.10 must be built non-monolithic (same reason as above)
ARG BUILD_PIP_PACKAGE=0
RUN TF_MINOR=$(echo ${TF_VERSION} | cut -d. -f2) && \
    TF_MAJOR=$(echo ${TF_VERSION} | cut -d. -f1) && \
    NON_MONO=$(awk "BEGIN {print (($TF_MAJOR > 2) || ($TF_MAJOR == 2 && $TF_MINOR >= 10)) ? 1 : 0}") && \
    USE_SIG_BUILD=$(awk "BEGIN {print (($TF_MAJOR > 2) || ($TF_MAJOR == 2 && $TF_MINOR >= 16)) ? 1 : 0}") && \
    CUDA_CONFIG="cuda" && \
    EXTRA_COPTS=$([ "$USE_SIG_BUILD" = "1" ] && echo "--copt=-Wno-error=unused-command-line-argument --host_copt=-Wno-error=unused-command-line-argument --copt=-Wno-error=gnu-offsetof-extensions --host_copt=-Wno-error=gnu-offsetof-extensions" || echo "") && \
    if [ "${BUILD_PIP_PACKAGE}" = "1" ]; then \
        if [ "${GPU_POSTFIX}" = "-gpu" ]; then \
            if [ "$NON_MONO" = "1" ]; then \
                bazel build --jobs ${JOBS} --config=${CUDA_CONFIG} --config=opt ${EXTRA_COPTS} --verbose_failures tensorflow/tools/pip_package:build_pip_package; \
            else \
                bazel build --jobs ${JOBS} --config=${CUDA_CONFIG} --config=opt --config=monolithic ${EXTRA_COPTS} --verbose_failures tensorflow/tools/pip_package:build_pip_package; \
            fi; \
        else \
            if [ "$NON_MONO" = "1" ]; then \
                bazel build --jobs ${JOBS} --config=opt ${EXTRA_COPTS} --verbose_failures tensorflow/tools/pip_package:build_pip_package; \
            else \
                bazel build --jobs ${JOBS} --config=opt --config=monolithic ${EXTRA_COPTS} --verbose_failures tensorflow/tools/pip_package:build_pip_package; \
            fi; \
        fi; \
        pip install patchelf && \
        ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow/pip ; \
    else \
        mkdir -p /tmp/tensorflow/pip && \
        touch /tmp/tensorflow/pip/tensorflow-dummy.whl ; \
    fi

# build protobuf from source, same version as TensorFlow is using
# TF < 2.16 declares protobuf in workspace*.bzl; TF >= 2.16 uses MODULE.bazel (bzlmod).
# protobuf < 4.x uses autoconf/make; protobuf >= 4.x uses CMake.
WORKDIR /
RUN apt-get install -y autoconf automake libtool curl make g++ unzip wget cmake && \
    PROTOBUF_URL=$(grep -Eho "https://github.com/protocolbuffers/protobuf/archive/.*\.(zip|tar\.gz)" tensorflow/tensorflow/workspace*.bzl 2>/dev/null | head -1) && \
    if [ -z "$PROTOBUF_URL" ]; then \
        PROTOBUF_VER=$(grep -Eo 'name\s*=\s*"protobuf",\s*version\s*=\s*"[0-9.]+"' tensorflow/MODULE.bazel 2>/dev/null | grep -Eo '"[0-9.]+"' | tail -1 | tr -d '"'); \
        if [ -n "$PROTOBUF_VER" ]; then \
            PROTOBUF_URL="https://github.com/protocolbuffers/protobuf/archive/v${PROTOBUF_VER}.tar.gz"; \
        fi; \
    fi && \
    PROTOBUF_VERSION=$(echo "$PROTOBUF_URL" | grep -Eo "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[0-9a-f]{40})") && \
    wget -q "$PROTOBUF_URL" -O protobuf.archive && \
    (unzip -q protobuf.archive || tar -xzf protobuf.archive) && \
    rm protobuf.archive && \
    mv protobuf-$PROTOBUF_VERSION protobuf && \
    cd protobuf && \
    if [ -f autogen.sh ]; then \
        ./autogen.sh && \
        ./configure --prefix=/usr/local && \
        make -j $(nproc) && \
        make install; \
    else \
        cmake -Bcmake_build \
            -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DCMAKE_BUILD_TYPE=Release \
            -Dprotobuf_BUILD_TESTS=OFF && \
        cmake --build cmake_build -j $(nproc) && \
        cmake --install cmake_build; \
    fi && \
    ldconfig

# --- deb-package stage providing libtensorflow-cc.deb -------------------------
FROM ubuntu:${UBUNTU_CODENAME} as deb-package

ARG TARGETARCH
ARG TF_VERSION
ARG GPU_POSTFIX

# create package structure
WORKDIR /libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX}
RUN mkdir -p usr/local/include/bin usr/local/include usr/local/lib/ usr/local/lib/cmake/tensorflow
COPY DEBIAN DEBIAN
COPY cmake/TensorFlowConfig.cmake usr/local/lib/cmake/tensorflow/TensorFlowConfig.cmake
COPY --from=build /tensorflow/bazel-bin/tensorflow/include  usr/local/include/tensorflow
COPY --from=build /tensorflow/bazel-bin/tensorflow/lib      usr/local/lib/tensorflow
COPY --from=build /usr/local/bin/protoc                     usr/local/bin/protoc
COPY --from=build /usr/local/include/google                 usr/local/include/google
COPY --from=build /usr/local/lib                            usr/local/lib/protobuf
RUN cp -d usr/local/lib/tensorflow/lib* usr/local/lib/protobuf/lib* usr/local/lib/ && \
    rm -rf usr/local/lib/tensorflow usr/local/lib/protobuf
RUN sed -i "s/TF_VERSION/$TF_VERSION/" DEBIAN/control
RUN sed -i "s/TARGETARCH/$TARGETARCH/" DEBIAN/control

# build .deb
WORKDIR /
RUN dpkg-deb --build --root-owner-group libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX} && \
    rm -rf libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX}/

# copy pip package, if built
ARG BUILD_PIP_PACKAGE
COPY --from=build /tmp/tensorflow/pip/tensorflow*.whl /

# --- final stage with TensorFlow Python and C++ Library -----------------------
FROM --platform=amd64 ${FINAL_BASE_AMD64} as final-amd64

FROM --platform=arm64 ubuntu:${UBUNTU_CODENAME} as final-base-arm64

FROM --platform=arm64 rwthika/cuda:11.8-cudnn-trt-ubuntu20.04 as final-base-arm64-gpu

FROM "final-base-arm64${GPU_POSTFIX}" as final-arm64

# copy and install pip package, if built (not present in base image)
ARG BUILD_PIP_PACKAGE
COPY --from=deb-package /tensorflow*.whl /
RUN if [ "${BUILD_PIP_PACKAGE}" = "1" ]; then \
        apt-get update && \
        apt-get install -y python3-pip && \
        python3 -m pip install --no-cache /tensorflow*.whl && \
        rm -rf /var/lib/apt/lists/*; \
    fi && \
    rm -rf /tensorflow*.whl

FROM "final-${TARGETARCH}" as final

ARG DEBIAN_FRONTEND=noninteractive
ARG TF_VERSION
ARG GPU_POSTFIX
ARG UBUNTU_CODENAME=focal

# make sure gcc is installed
RUN apt-get update && \
    apt-get install -y build-essential && \
    rm -rf /var/lib/apt/lists/*

# install gcc 11 for 2.12.0, 2.12.1, 2.13.0 on focal only
# (noble ships gcc-13 by default which is sufficient)
# https://stackoverflow.com/a/67453352/7264974
RUN if [ "${UBUNTU_CODENAME}" = "focal" ] && { [ "${TF_VERSION}" = "2.12.0" ] || [ "${TF_VERSION}" = "2.12.1" ] || [ "${TF_VERSION}" = "2.13.0" ]; }; then \
        apt-get update && \
	    apt-get install -y software-properties-common && \
        add-apt-repository ppa:ubuntu-toolchain-r/test && \
        apt-get install -y gcc-11 g++-11 && \
        rm -rf /var/lib/apt/lists/* && \
        update-alternatives --remove-all cpp && \
        update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9 --slave /usr/bin/gcov gcov /usr/bin/gcov-9 --slave /usr/bin/gcc-ar gcc-ar /usr/bin/gcc-ar-9 --slave /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-9 --slave /usr/bin/cpp cpp /usr/bin/cpp-9 && \
        update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 --slave /usr/bin/g++ g++ /usr/bin/g++-11 --slave /usr/bin/gcov gcov /usr/bin/gcov-11 --slave /usr/bin/gcc-ar gcc-ar /usr/bin/gcc-ar-11 --slave /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-11  --slave /usr/bin/cpp cpp /usr/bin/cpp-11 ; \
    fi

# install TensorFlow C++ API incl. protobuf
COPY --from=deb-package /libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX}.deb /tmp
RUN dpkg -i /tmp/libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX}.deb && \
    ldconfig && \
    rm /tmp/libtensorflow-cc_${TF_VERSION}${GPU_POSTFIX}.deb
