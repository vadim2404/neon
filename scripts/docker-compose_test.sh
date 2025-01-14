#!/bin/bash

# this is a shortcut script to avoid duplication in CI
set -eux -o pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMPOSE_FILE=$SCRIPT_DIR/../docker-compose/docker-compose.yml

COMPUTE_CONTAINER_NAME=dockercompose_compute_1
SQL="CREATE TABLE t(key int primary key, value text); insert into t values(1,1); select * from t;"
PSQL_OPTION="-h localhost -U cloud_admin -p 55433 -c '$SQL' postgres"

cleanup() {
	echo "show container information"
	docker ps
	docker-compose -f $COMPOSE_FILE logs
	echo "stop containers..."
	docker-compose -f $COMPOSE_FILE down
}

echo "clean up containers if exists"
cleanup

for pg_version in 14 15; do
	echo "start containers (pg_version=$pg_version)."
	PG_VERSION=$pg_version TAG=latest docker-compose -f $COMPOSE_FILE up --build -d

	echo "wait until the compute is ready. timeout after 60s. "
	cnt=0
	while sleep 1; do
		# check timeout
		cnt=`expr $cnt + 1`
		if [ $cnt -gt 60 ]; then
			echo "timeout before the compute is ready."
			cleanup
			exit 1
		fi

		# check if the compute is ready
		set +o pipefail
		result=`docker-compose -f $COMPOSE_FILE logs "compute_is_ready" | grep "accepting connections" | wc -l`
		set -o pipefail
		if [ $result -eq 1 ]; then
			echo "OK. The compute is ready to connect."
			echo "execute simple queries."
			docker exec -it $COMPUTE_CONTAINER_NAME /bin/bash -c "psql $PSQL_OPTION"
			cleanup
			break
		fi
	done
done
