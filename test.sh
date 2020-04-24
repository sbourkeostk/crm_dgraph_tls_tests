#!/bin/bash

set -e

WORK_DIR="/tmp/dgraph_tests_${RANDOM}"

if [[ "${DO_TLS}" -ne 1 ]]; then
    echo "Doing Non-TLS test. Set DO_TLS=1 for TLS test."
    DO_TLS="0"
else
    echo "Doing TLS test."
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
mkdir -p ${WORK_DIR}
echo "Work dir is ${WORK_DIR}."
cd ${WORK_DIR}

#DOCKER_IMAGE="dgraph/dgraph:latest"
DOCKER_IMAGE="crm/dgraph:v20.03.0-oss"
CLIENT_NAME="testing"

ip_addr=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
docker_net="dgraph_net_${RANDOM}"

# node_list should be a list of all names that will act as dgraph (alpha) servers
# Include hostname,fqdn,ip to be safe.
node_list="localhost,${ip_addr}"

docker network create ${docker_net}
echo "docker network is ${docker_net}."

mkdir -p ${WORK_DIR}/zero ${WORK_DIR}/alpha ${WORK_DIR}/tls
echo "Starting zero."
zero_id=$(docker run --rm -d \
           --name dgraph-zero \
           --network ${docker_net} \
           -p 5080:5080 \
           -p 6080:6080 \
           -v ${WORK_DIR}/zero:/dgraph \
           -v ${WORK_DIR}/tls:/tls \
           ${DOCKER_IMAGE} \
	   dgraph zero --my=${ip_addr}:5080)
sleep 5

# Node cert for alpha(s)
echo "Creating server cert."
docker exec -it dgraph-zero dgraph cert --dir /tls -n ${node_list}

if [[ "$DO_TLS" -eq 1 ]]; then
    tls_args="--tls_dir /tls --tls_client_auth REQUIREANDVERIFY"
else
    tls_args=""
fi
echo "Starting alpha."
alpha_id=$(docker run --rm -d \
           --name dgraph-alpha \
           --network ${docker_net} \
           -p 7080:7080 \
           -p 8080:8080 \
           -p 9080:9080 \
	   -v ${WORK_DIR}/alpha:/dgraph \
           -v ${WORK_DIR}/tls:/tls \
           ${DOCKER_IMAGE} \
           dgraph alpha --lru_mb=1024 \
                        --zero=${ip_addr}:5080 \
                        --my=${ip_addr}:7080 \
                        ${tls_args})
sleep 5

# Client cert
echo "Creating client cert."
docker exec dgraph-zero dgraph cert --dir /tls -c ${CLIENT_NAME}
docker exec dgraph-zero chmod a+r /tls/client.${CLIENT_NAME}.key

# Tests
set +e # Turn off quit-on-error
echo; echo
echo "Testing HTTP."
curl http://${ip_addr}:8080/state
echo; echo
echo "Testing HTTPS, no client cert."
curl --cacert ${WORK_DIR}/tls/ca.crt https://${ip_addr}:8080/state
echo; echo
echo "Testing HTTPS, with client cert."
curl --cacert ${WORK_DIR}/tls/ca.crt \
     --cert ${WORK_DIR}/tls/client.${CLIENT_NAME}.crt \
     --key ${WORK_DIR}/tls/client.${CLIENT_NAME}.key \
     https://${ip_addr}:8080/state
echo; echo

echo "Testing gRPC without TLS."
docker run --rm -it -v ${script_dir}/python:/tests crm/pydgraph:v20.03.0 python3 /tests/grpc_test.py ${ip_addr}:9080
echo; echo
echo "Testing gRPC with TLS."
docker run --rm -it \
           -v ${script_dir}/python:/tests \
           -v ${WORK_DIR}:${WORK_DIR} \
	   crm/pydgraph:v20.03.0 \
               python3 /tests/grpc_tls_test.py \
                   --cacert ${WORK_DIR}/tls/ca.crt \
                   --cert ${WORK_DIR}/tls/client.${CLIENT_NAME}.crt \
                   --key ${WORK_DIR}/tls/client.${CLIENT_NAME}.key \
                   ${ip_addr}:9080
echo; echo
set -e

echo "Killing images."
docker kill ${alpha_id} ${zero_id}
echo "Cleaning up. Need sudo because files created as root in container."
cleanup_cmd="sudo rm -rf ${WORK_DIR}"
echo ${cleanup_cmd}
${cleanup_cmd}
docker network rm ${docker_net}
