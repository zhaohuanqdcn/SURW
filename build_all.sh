#!/bin/bash
set -e

docker build -f dockerfiles/Dockerfile.base -t schedfuzz-base .
docker build -f dockerfiles/Dockerfile.period -t fuzz-period .
docker build -f dockerfiles/Dockerfile.zigsched.period -t zig-period .
docker build -f dockerfiles/Dockerfile.racebench -t fuzz-racebench .
docker build -f dockerfiles/Dockerfile.zigsched.racebench -t zig-racebench .

docker build -f dockerfiles/Dockerfile.lightftp -t fuzz-lftp .
docker build -f dockerfiles/Dockerfile.zigsched.lightftp -t zig-lftp .