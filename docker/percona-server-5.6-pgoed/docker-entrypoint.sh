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

# Generated provisioning SQL uses a known session mode. Quote values using SQL's
# doubled quote syntax so passwords retain literal backslashes and newlines even
# when the server's configured sql_mode contains NO_BACKSLASH_ESCAPES.
sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

sql_identifier() {
  local value="$1"
  value="${value//\`/\`\`}"
  printf '`%s`' "$value"
}

mysql_provision() {
  {
    printf "%s\n" "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';"
    cat
  } | "${mysql[@]}" --binary-mode=1 --default-character-set=utf8mb4 "$@"
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
  if ! errors="$( "${toRun[@]}" 2>&1 >/dev/null )"; then
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
  # Read a bounded amount so pipefail never sees tr die from head's SIGPIPE.
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
  printf '\n'
}

if [ "$1" = 'mysqld' ] && [ -z "$wantHelp" ]; then
  # NOTE: Percona Server 5.6 has no --initialize support and no
  # percona_telemetry_disable variable. Data directory bootstrap therefore
  # uses scripts/mysql_install_db from the tarball, and no telemetry flag is
  # appended (unlike the 8.0/8.4 entrypoints).

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
    # mysql_install_db on 5.6 creates root@localhost with an empty password,
    # anonymous users, and the test database; both are pruned below.
    # Its bundled SQL uses backslash escapes, so override sql_mode only during
    # this legacy bootstrap; the server still receives all requested options.
    "${PS_BASEDIR}/scripts/mysql_install_db" \
      --datadir="${DATADIR}" \
      --basedir="${PS_BASEDIR}" \
      --user="$(id -un)" \
      "${@:2}" \
      --sql-mode=""
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
    rootAccounts="'root'@'localhost'"
    file_env 'MYSQL_ROOT_HOST' '%'
    rootPasswordSql="$(sql_literal "$MYSQL_ROOT_PASSWORD")"
    rootHostSql="$(sql_literal "$MYSQL_ROOT_HOST")"
    if [ -n "$MYSQL_ROOT_HOST" ] && [ "$MYSQL_ROOT_HOST" != 'localhost' ]; then
      rootAccounts+=", 'root'@${rootHostSql}"
      read -r -d '' rootCreate <<-EOSQL || true
				CREATE USER 'root'@${rootHostSql} IDENTIFIED BY ${rootPasswordSql} ;
				GRANT ALL ON *.* TO 'root'@${rootHostSql} WITH GRANT OPTION ;
EOSQL
    fi

    mysql_provision <<-EOSQL
			SET @@SESSION.SQL_LOG_BIN=0;

			DELETE FROM mysql.user WHERE user NOT IN ('root') OR host NOT IN ('localhost') ;
			SET PASSWORD FOR 'root'@'localhost' = PASSWORD(${rootPasswordSql}) ;
			GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
			${rootCreate}
			DELETE FROM mysql.db WHERE Db LIKE 'test%' ;
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
EOSQL

    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
      mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
    fi

    file_env 'MYSQL_DATABASE'
    if [ "$MYSQL_DATABASE" ]; then
      databaseSql="$(sql_identifier "$MYSQL_DATABASE")"
      printf 'CREATE DATABASE IF NOT EXISTS %s;\n' "$databaseSql" | mysql_provision
      mysql+=( --database="$MYSQL_DATABASE" )
    fi

    file_env 'MYSQL_USER'
    file_env 'MYSQL_PASSWORD'
    if [ "$MYSQL_USER" ] && [ "$MYSQL_PASSWORD" ]; then
      userSql="$(sql_literal "$MYSQL_USER")"
      passwordSql="$(sql_literal "$MYSQL_PASSWORD")"
      printf "CREATE USER %s@'%%' IDENTIFIED BY %s;\n" "$userSql" "$passwordSql" | mysql_provision

      if [ "$MYSQL_DATABASE" ]; then
        printf "GRANT ALL ON %s.* TO %s@'%%';\n" "$databaseSql" "$userSql" | mysql_provision
      fi

      printf 'FLUSH PRIVILEGES;\n' | mysql_provision
    fi

    echo
    ls /docker-entrypoint-initdb.d/ > /dev/null
    for f in /docker-entrypoint-initdb.d/*; do
      process_init_file "$f" "${mysql[@]}"
    done

    if [ -n "${MYSQL_ONETIME_PASSWORD:-}" ]; then
      "${mysql[@]}" <<-EOSQL
				UPDATE mysql.user SET password_expired = 'y' WHERE user = 'root' ;
				FLUSH PRIVILEGES ;
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
