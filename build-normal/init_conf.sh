#!/bin/bash

: ${1?"Usage: $0 MYSQL_DATA_DIR MYSQL_VER"}
: ${2?"Usage: $0 MYSQL_DATA_DIR MYSQL_VER"}
datadir=$1
MYSQL_VER=$2
basedir=$3

### setup my.cnf, as mariadb-libs installed on previous steps, add a /etc/my.cnf.d/perf.cnf is OK
server_id=`dd status=none bs=128 count=1 if=/dev/urandom | base64 | tr -dc '1-9' | fold -w 4 | less | head -n 1`
mem=$(free|grep Mem|awk '{print$2}')
totmem=$(echo "$mem*1024"|bc)
pct=75
# pct = 40 shared host
pool_max=$(echo "$totmem*$pct/100/1024/1024/64 * 64"|bc)
# set to max 4800, so we can benchmark with a 10G dataset for a little io-bound workload
pool_max=$((pool_max<4800 ? pool_max : 4800))
logfile_size=$(echo "$pool_max/8"|bc)
pool_chunk_size=$(($logfile_size>1024?128:$logfile_size/8))
logfile_size=$(($logfile_size<2048?$logfile_size:2048))

JEMALLOC="/usr/lib64/libjemalloc.so.1"
[[ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so ]] && JEMALLOC=/usr/lib/x86_64-linux-gnu/libjemalloc.so

cat <<EOF
[mysqld_safe]
malloc-lib=$JEMALLOC
datadir=$datadir
socket=${datadir}/mysql.sock

[client]
socket=${datadir}/mysql.sock

[mysqld]
server_id=${server_id}
datadir=$datadir
plugin-dir=$basedir/lib/plugin
socket=${datadir}/mysql.sock
log-error=${datadir}/mysql.err.log
pid-file=${datadir}/mysql.pid

# below has good default when >= 5.6
# default_storage_engine=innodb
# innodb_stats_on_metadata=OFF

# below has good default when >= 5.7
loose_innodb_adaptive_hash_index_partitions=8

# MySQL 5.5 4, >=5.6 8~16, 5.7 default = 16
# innodb_buffer_pool_instances=4

innodb_buffer_pool_size=${pool_max}M
# chunk_size only in >= 5.7
loose_innodb_buffer_pool_chunk_size=${pool_chunk_size}M
innodb_log_file_size=${logfile_size}M
innodb_flush_log_at_trx_commit=2
innodb_flush_method=O_DIRECT

# increment it only on big-box with test
innodb_thread_concurrency=8
# raid10 8*15k
# innodb_io_capacity=600
# innodb_io_capacity_max=1000

# default is 25, high if you won't more warm db but more space usage, only avialible >=5.6 or >= percona 5.1
loose_innodb_buffer_pool_dump_at_shutdown=1
loose_innodb_buffer_pool_load_at_startup=1
loose_innodb_buffer_pool_dump_pct=100

# only used on 5.6, below has good default on 5.7, 5.5 don't have it
innodb_checksum_algorithm=crc
table_open_cache_instances=16

# query_cache_type=OFF
# query_cache_size=0
performance_schema=OFF

# slave settings
master_info_repository = TABLE
relay_log_info_repository = TABLE
gtid_mode = on
log_bin=${datadir}/mysqlbin
max_binlog_size=512M
binlog_format=ROW
binlog_row_image=minimal
log-slave-updates
loose_max_binlog_files=4
loose_binlog_space_limit=2G
enforce_gtid_consistency = 1
slave_skip_errors = ddl_exist_errors

# compatible settings
innodb_strict_mode = 1
innodb_file_per_table=1
sql_mode = "STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO"
character_set_server=utf8mb4
lower_case_table_names=1
skip_name_resolve
# transaction_isolation = READ-COMMITTED
explicit_defaults_for_timestamp = 1

sync_binlog=10000
# unify for benchmark, 5.7 is on as default while 5.6 is off
ssl=0

### rocksdb part
##loose-rocksdb_max_open_files=-1
##loose-rocksdb_max_background_jobs=8
##loose-rocksdb_max_total_wal_size=600M
##loose-rocksdb_block_size=16384
##loose-rocksdb_table_cache_numshardbits=6

# rate limiter
##loose-rocksdb_bytes_per_sync=16777216
##loose-rocksdb_wal_bytes_per_sync=4194304
#rocksdb_rate_limiter_bytes_per_sec=104857600 #100MB/s
#
# # triggering compaction if there are many sequential deletes
##loose-rocksdb_compaction_sequential_deletes_count_sd=1
##loose-rocksdb_compaction_sequential_deletes=199999
##loose-rocksdb_compaction_sequential_deletes_window=200000

##loose-rocksdb_default_cf_options="write_buffer_size=256m;target_file_size_base=32m;max_bytes_for_level_base=512m;max_write_buffer_number=4;level0_file_num_compaction_trigger=4;level0_slowdown_writes_trigger=20;level0_stop_writes_trigger=30;max_write_buffer_number=4;block_based_table_factory={cache_index_and_filter_blocks=1;filter_policy=bloomfilter:10:false;whole_key_filtering=0};level_compaction_dynamic_level_bytes=true;optimize_filters_for_hits=true;memtable_prefix_bloom_size_ratio=0.05;prefix_extractor=capped:12;compaction_pri=kMinOverlappingRatio;compression=kLZ4Compression;bottommost_compression=kLZ4Compression;compression_opts=-14:4:0"

##loose-rocksdb_max_subcompactions=4
##loose-rocksdb_compaction_readahead_size=16m

##loose-rocksdb_use_direct_reads=ON
##loose-rocksdb_use_direct_io_for_flush_and_compaction=ON

##loose-rocksdb_block_cache_size=4800M
EOF

