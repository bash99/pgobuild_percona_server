#!/bin/bash

datadir=$1

### setup my.cnf, as mariadb-libs installed on previous steps, add a /etc/my.cnf.d/perf.cnf is OK
server_id=`dd status=none bs=128 count=1 if=/dev/urandom | base64 | tr -dc '1-9' | fold -w 4 | less | head -n 1`
mem=$(free|grep Mem|awk '{print$2}')
totmem=$(echo "$mem*1024"|bc)
pct=75
# pct = 40 shared host
pool_max=$(echo "$totmem*$pct/100/1024/1024/64 * 64"|bc)
pool_max=$((pool_max<4800 ? pool_max : 4800))
logfile_size=$(echo "$pool_max/8"|bc)
pool_chunk_size=$(($logfile_size>1024?128:$logfile_size/8))
logfile_size=$(($logfile_size<2048?$logfile_size:2048))

cat > $datadir/../etc/my.automem.cnf <<EOF
[mysqld_safe]
malloc-lib=/usr/lib64/libjemalloc.so.1
datadir=$datadir
socket=${datadir}/mysql.sock

[client]
socket=${datadir}/mysql.sock

[mysqld]
server_id=${server_id}
datadir=$datadir
socket=${datadir}/mysql.sock
log-error=${datadir}/mysql.err.log
pid-file=${datadir}/mysql.pid

# below has good default when >= 5.6
# default_storage_engine=innodb
# innodb_stats_on_metadata=OFF

# below has good default when >= 5.7
# innodb_adaptive_hash_index_parts=8

# MySQL 5.5 4, >=5.6 8~16, 5.7 default = 16
# innodb_buffer_pool_instances=4

innodb_buffer_pool_size=${pool_max}M
innodb_buffer_pool_chunk_size=${pool_chunk_size}M
innodb_log_file_size=${logfile_size}M
innodb_flush_log_at_trx_commit=2
sync_binlog=0
innodb_flush_method=O_DIRECT

# increment it only on big-box with test
innodb_thread_concurrency=8
# raid10 8*15k
# innodb_io_capacity=600
# innodb_io_capacity_max=1000

# default is 25, high if you won't more warm db but more space usage, only avialible >=5.6 or >= percona 5.1
innodb_buffer_pool_dump_pct=100

# only used on 5.6, below has good default on 5.7, 5.5 don't have it
# innodb_checksum_algorithm=crc
# table_open_cache_instances=16

# query_cache_type=OFF
# query_cache_size=0
performance_schema=OFF

# slave settings
master_info_repository = TABLE
relay_log_info_repository = TABLE
gtid_mode = on
enforce_gtid_consistency = 1
slave_skip_errors = ddl_exist_errors

# compatible settings
innodb_strict_mode = 1
sql_mode = "STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
character_set_server=utf8mb4
lower_case_table_names=1
skip_name_resolve
# transaction_isolation = READ-COMMITTED
explicit_defaults_for_timestamp = 1

EOF

