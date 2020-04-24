#!/bin/bash

set -e

BUILD_DIR="/tmp/dgraph_build"
DGRAPH_GIT_TAG="v20.03.0"
GO_IMAGE_TAG="golang:1.14.2" # Image for building dgraph

# Get dgraph source
mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}
git clone https://github.com/dgraph-io/dgraph
(cd dgraph; git checkout tags/${DGRAPH_GIT_TAG} -b ${DGRAPH_GIT_TAG})

# Compile dgraph and build docker image
docker run --rm -v ${BUILD_DIR}:/src ${GO_IMAGE_TAG} bash -c "cd /src/dgraph; GOOS=linux make BUILD_TAGS=oss dgraph"
mkdir linux
cp dgraph/dgraph/dgraph linux
docker build -f dgraph/contrib/Dockerfile -t crm/dgraph:${DGRAPH_GIT_TAG}-oss .
