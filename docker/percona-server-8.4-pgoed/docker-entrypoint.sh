#!/bin/bash
set -eo pipefail
shopt -s nullglob

# If command starts with an option, prepend mysqld.
if [ "${1:0:1}" = '-' ]; then
  set -- mysqld "$@"
fi

# Skip setup if they want an option that stops mysqld.
wantHelp=
for arg; do
  case "$arg" in
    -'?'|--help|--print-defaults|-V|--version)
      wantHelp=1
      break
      ;;
  esac
done

# usage: file_env VAR [DEFAULT]
# Allows "$VAR_FILE" to fill in the value of "$VAR" from a file (Docker secrets).
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

process_init_file() {
  local f="$1"; shift
  local mysql=( "$@" )

  case "$f" in
    *.sh)     echo "$0: running $f"; . "$f" ;;
    *.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
    *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
    *)        echo "$0: ignoring $f" ;;
  esac
  echo
}

_check_config() {
  toRun=( "$@" --verbose --help )
  if ! errors="$("${toRun[@]}" 2>&1 >/dev/null)"; then
    cat >&2 <<-EOM

			ERROR: mysqld failed while attempting to check config
			command was: "${toRun[*]}"

			$errors
EOM
    exit 1
  fi
}

_get_config() {
  local conf="$1"; shift
  "$@" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null \
    | awk '$1 == "'"$conf"'" && /^[^ \t]/ { sub(/^[^ \t]+[ \t]+/, ""); print; exit }'
}

enable_jemalloc_preload() {
  if [ -n "${LD_PRELOAD:-}" ]; then
    return 0
  fi

  local candidate
  for candidate in /usr/lib64/libjemalloc.so.2 /usr/lib64/libjemalloc.so.1; do
    if [ -r "$candidate" ]; then
      export LD_PRELOAD="$candidate"
      return 0
    fi
  done

  echo >&2 "warning: jemalloc library not found under /usr/lib64; mysqld will start without LD_PRELOAD"
  return 0
}

random_password() {
  if command -v pwmake >/dev/null 2>&1; then
    pwmake 128
    return 0
  fi
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64
  echo
}

if [ "$1" = 'mysqld' ] && [ -z "$wantHelp" ]; then
  if [ "${PERCONA_TELEMETRY_DISABLE:-1}" != "0" ]; then
    set -- "$@" --percona_telemetry_disable=1
  fi

  _check_config "$@"
  enable_jemalloc_preload

  DATADIR="$(_get_config 'datadir' "$@")"

  if [ ! -d "$DATADIR/mysql" ]; then
    file_env 'MYSQL_ROOT_PASSWORD'
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ -z "${MYSQL_ALLOW_EMPTY_PASSWORD:-}" ] && [ -z "${MYSQL_RANDOM_ROOT_PASSWORD:-}" ]; then
      echo >&2 'error: database is uninitialized and password option is not specified'
      echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
      exit 1
    fi

    mkdir -p "$DATADIR"

    echo 'Initializing database'
    "$@" --initialize-insecure
    echo 'Database initialized'

    SOCKET="$(_get_config 'socket' "$@")"
    "$@" --skip-networking --socket="${SOCKET}" &
    pid="$!"

    mysql=( mysql --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" --password="" )

    for i in {120..0}; do
      if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
        break
      fi
      echo 'MySQL init process in progress...'
      sleep 1
    done
    if [ "$i" = 0 ]; then
      echo >&2 'MySQL init process failed.'
      exit 1
    fi

    if [ -z "${MYSQL_INITDB_SKIP_TZINFO:-}" ]; then
      (
        echo "SET @@SESSION.SQL_LOG_BIN = off;"
        mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/'
      ) | "${mysql[@]}" mysql
    fi

    if [ -n "${MYSQL_RANDOM_ROOT_PASSWORD:-}" ]; then
      MYSQL_ROOT_PASSWORD="$(random_password)"
      echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
    fi

    rootCreate=
    file_env 'MYSQL_ROOT_HOST' '%'
    if [ -n "$MYSQL_ROOT_HOST" ] && [ "$MYSQL_ROOT_HOST" != 'localhost' ]; then
      read -r -d '' rootCreate <<-EOSQL || true
				CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
				GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;
EOSQL
    fi

    "${mysql[@]}" <<-EOSQL
			SET @@SESSION.SQL_LOG_BIN=0;

			DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'mysql.infoschema', 'mysql.session', 'root') OR host NOT IN ('localhost') ;
			ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
			${rootCreate}
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
EOSQL

    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
      mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
    fi

    file_env 'MYSQL_DATABASE'
    if [ "$MYSQL_DATABASE" ]; then
      echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
      mysql+=( "$MYSQL_DATABASE" )
    fi

    file_env 'MYSQL_USER'
    file_env 'MYSQL_PASSWORD'
    if [ "$MYSQL_USER" ] && [ "$MYSQL_PASSWORD" ]; then
      echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"

      if [ "$MYSQL_DATABASE" ]; then
        echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
      fi

      echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
    fi

    echo
    ls /docker-entrypoint-initdb.d/ > /dev/null
    for f in /docker-entrypoint-initdb.d/*; do
      process_init_file "$f" "${mysql[@]}"
    done

    if [ -n "${MYSQL_ONETIME_PASSWORD:-}" ]; then
      "${mysql[@]}" <<-EOSQL
				ALTER USER 'root'@'%' PASSWORD EXPIRE;
EOSQL
    fi

    if ! kill -s TERM "$pid" || ! wait "$pid"; then
      echo >&2 'MySQL init process failed.'
      exit 1
    fi

    echo
    echo 'MySQL init process done. Ready for start up.'
    echo
  fi

  if [ -n "${MYSQL_INIT_ONLY:-}" ]; then
    echo 'Initialization complete, now exiting!'
    exit 0
  fi
fi

exec "$@"
