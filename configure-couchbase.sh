#!/bin/bash

start_server() {

    echo -n "* Starting couchbase "
    export HOME=/var/lib/couchbase
    exec /etc/service/couchbase-server/run 2>&1 &
    CB_PID=$!

    while ! curl --output /dev/null --silent --head --fail http://localhost:8091; do
        sleep 1 && echo -n ".";
    done;
    echo " started !"
}

is_only_service_key_value() {

    test $CB_SERVICES == "kv"
}

create_cluster() {

    echo "* Creating couchbase cluster"
    if [[ "$CB_SERVICES" == "kv" ]]; then
        echo "* Setting memory quota for kv only"
        curl -sS -X POST http://127.0.0.1:8091/pools/default \
            -d "memoryQuota=${CB_RAM_SIZE}"
    else
        echo "* Setting memory quota"
        curl -sS -X POST http://127.0.0.1:8091/pools/default \
            -d "memoryQuota=${CB_RAM_SIZE}" \
            -d "indexMemoryQuota=${CB_INDEX_RAM_SIZE}" \
            -d "ftsMemoryQuota=${CB_FTS_RAM_SIZE}"
    fi
}

setup_services() {

    echo "* Setting up services"
    curl -sS -X POST http://127.0.0.1:8091/node/controller/setupServices \
        -d "services=${CB_SERVICES}"
}

setup_storage() {

    echo "* Setting up storage"
    curl -sS -X POST http://127.0.0.1:8091/settings/indexes \
        -d "storageMode=forestdb" | python -c 'import json,sys; print("\n".join(["  %s: %s" % (k, v) for k, v in json.load(sys.stdin).items()]))'
}

setup_credentials() {

    echo "* Setting up credentials and port"
    curl -sS -X POST http://127.0.0.1:8091/settings/web \
        -d "username=${CB_ADMIN_USER}&password=${CB_ADMIN_PWD}&port=8091&" | python -c 'import json,sys; print("\n".join(["  %s: %s" % (k, v) for k, v in json.load(sys.stdin).items()]))'
}

setup_bucket() {

    if [[ ! -z "$CB_BUCKET" ]]; then
        echo "* Setting up bucket"
        curl -sS -u $CB_ADMIN_USER:$CB_ADMIN_PWD -X POST http://127.0.0.1:8091/pools/default/buckets \
            -d name=$CB_BUCKET \
            -d bucketType=$CB_BUCKET_TYPE \
            -d ramQuotaMB=$CB_BUCKET_RAM_QUOTA_MB \
            -d authType=$CB_BUCKET_AUTH_TYPE \
            -d saslPassword=$CB_BUCKET_PASSWORD
    fi
}

is_cluster_configured() {

    couchbase-cli server-list -c 127.0.0.1:8091 -u "${CB_ADMIN_USER}" -p "${CB_ADMIN_PWD}" 1>/dev/null 2>&1;
}

configure_if_necessary() {

    if ! is_cluster_configured; then
        create_cluster
        setup_services
        setup_storage
        setup_credentials
        setup_bucket
    fi
}

echo "starting" > /tmp/status

CB_SERVICES="${CB_SERVICES:-kv,index,n1ql,fts}"
CB_RAM_SIZE="${CB_RAM_SIZE:-512}"
CB_INDEX_RAM_SIZE="${CB_INDEX_RAM_SIZE:-256}"
CB_FTS_RAM_SIZE="${CB_FTS_RAM_SIZE:-256}"
CB_INDEX_STORAGE="${CB_INDEX_STORAGE:-forestdb}"
CB_BUCKET_TYPE="${CB_BUCKET_TYPE:-couchbase}"
CB_BUCKET_RAM_QUOTA_MB="${CB_BUCKET_RAM_QUOTA_MB:-128}"
CB_BUCKET_AUTH_TYPE="${CB_BUCKET_AUTH_TYPE:-sasl}"

start_server
configure_if_necessary

trap 'kill -TERM $CB_PID' TERM
trap 'kill -INT $CB_PID' INT

echo "ready" > /tmp/status

echo "* Setup finished -- Web UI available at http://<ip>:8091"
wait $CB_PID
trap - TERM INT
wait $CB_PID
EXIT_STATUS=$?