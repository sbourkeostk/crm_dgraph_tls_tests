# Tests for Dgraph + TLS

Build an OSS dgraph docker image:
```
./build_dgraph_oss.sh
```

Build a pydgraph docker image (used for gRPC tests):
```
cd python && ./build_pydgraph_image.sh
```

Run tests using the above images with and without TLS:
```
./test.sh
DO_TLS=1 ./test.sh
```
