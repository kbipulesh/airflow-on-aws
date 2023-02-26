#!/usr/bin/env bash

TRY_LOOP="20"

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 </dev/null; do
    j=$((j + 1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name $host... $j/$TRY_LOOP"
    sleep 5
  done
}

wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"

# Environment variables
. ./.env

case "$1" in
webserver)
  #    echo "Initializing database"
  #    exec airflow db init
  if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ] || [ "$AIRFLOW__CORE__EXECUTOR" = "SequentialExecutor" ]; then
    # With the "Local" and "Sequential" executors it should all run in one container.
    airflow scheduler &
  fi
  echo "Starting webserver"
  exec airflow webserver
  ;;
scheduler)
  echo "Running Airflow DB upgrade"
  exec airflow db upgrade &
  sleep 15
  echo "Starting scheduler"
  exec airflow "$@"
  ;;
worker | flower)
  sleep 15
  echo "Starting Celery"
  echo "$1"
  exec airflow celery "$@"
  ;;
version)
  exec airflow "$@"
  ;;
*)
  echo "Entrypoint Command"
  echo "$1"
  exec "$@"
  ;;
esac
