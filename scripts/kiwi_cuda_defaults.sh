#!/usr/bin/env bash

# Shared CUDA defaults for Kiwi Linux and hosted-notebook builds.
#
# The hosted-notebook target intentionally tracks Colab/Kaggle-style CUDA 12.8
# runtimes and avoids sm_60/P100 for MLX CUDA because current MLX CUDA kernels
# require compute_70 or newer.

: "${KIWI_CUDA_12_8_BASE_IMAGE:=nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_ARCHITECTURES:=70-real;75-real;80-real;89-real;90a-real}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_KERNEL_PROFILE:=kiwi_runtime}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_BUILD_PARALLEL:=3}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_IMAGE_TAG:=kiwi-array-colab-cuda128:zig-0.15.2}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_AUDITWHEEL_PLAT:=manylinux_2_35_x86_64}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_REPAIR_WHEEL:=0}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_ALLOW_REPAIR_FAILURE:=1}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_FAST_ARCHITECTURES:=75-real}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_FAST_KERNEL_PROFILE:=kiwi_runtime}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_FAST_REPAIR_WHEEL:=0}"
: "${KIWI_HOSTED_NOTEBOOK_CUDA_FAST_ALLOW_REPAIR_FAILURE:=1}"
: "${KIWI_CUDA_DISABLE_SM80_QMM:=1}"
