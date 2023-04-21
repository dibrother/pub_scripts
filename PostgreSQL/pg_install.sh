#!/bin/bash

# postgresql 相关目录
pg_port=5432
pg_dir=/app/pgsql
pg_datadir=${pg_dir}/data
pg_backupdir=${pg_dir}/backup
is_ssd=0
current_dir=$(cd $(dirname $0); pwd)

# pgbackrest 相关目录
pgbackrest_log_dir=/var/log/pgbackrest
pgbackrest_config_dir=/etc/pgbackrest


function system_disabe_selinux(){
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    systemctl disable firewalld.service
    systemctl stop firewalld.service    
}

function pg_yum_install(){
    # yum 安装
    yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    useradd postgres
    echo 'postgres' | passwd -f --stdin postgres
    yum install -y postgresql12-server postgresql12-contrib
    # 数据目录
    mkdir -p ${pg_dir}/data
    chown -R postgres:postgres ${pg_dir}
    chmod -R 700 ${pg_dir}
    # 更改数据目录
    sed -i 's#^Environment=PGDATA.*#Environment=PGDATA='${pg_datadir}'/#g' /usr/lib/systemd/system/postgresql-12.service
    systemctl daemon-reload
    # 初始化
    /usr/pgsql-12/bin/postgresql-12-setup initdb
    # 放开访问权限
    sed -i '87i host    all             all             0.0.0.0/0               md5' /root/pg_hba.conf
    # 动态参数配置
    shared_buffers="$(expr $(free -m|grep Mem|awk '{print $2}') / 4)MB"
    maintenance_work_mem="$(expr $(free -m|grep Mem|awk '{print $2}') / 16)MB"
    effective_cache_size="$(expr $(free -m|grep Mem|awk '{print $2}') / 2)MB"
    cpu_core=$(expr $(nproc) / 2)
    free_mem=$(free |grep Mem|awk '{print $2}')
    min_wal_size=$(expr $(free |grep Mem|awk '{print $2}') / 8192)
    max_wal_size=$(expr $(free |grep Mem|awk '{print $2}') / 2048)
    autovacuum_work_mem=$(expr ${free_mem} / 64)

    if [ $cpu_core -lt 1 ];then
        max_parallel_maintenance_workers=2
        max_parallel_workers_per_gather=2
    else
        max_parallel_maintenance_workers="$cpu_core"
        max_parallel_workers_per_gather="$cpu_core"
    fi

    if [ ${min_wal_size} -lt 256 ];then
        min_wal_size='256MB'
    elif [ ${min_wal_size} -gt 8192 ];then
        min_wal_size='8GB'
    else
        min_wal_size="${min_wal_size}MB"
    fi

    if [ ${max_wal_size} -lt 2048 ];then
        min_wal_size='2GB'
    elif [ ${max_wal_size} -gt 16384 ];then
        min_wal_size='16GB'
    else
        min_wal_size="${min_wal_size}MB"
    fi

    if [ $autovacuum_work_mem -lt 128 ];then
        autovacuum_work_mem="128MB"
    else
        autovacuum_work_mem="${autovacuum_work_mem}MB"
    fi

    if [ ${is_ssd} -eq 1 ];then
        random_page_cost=1.1 
    else
        random_page_cost=4
    fi

    # 配置 postgres.conf
    mv ${pg_datadir}/postgresql.conf  ${pg_datadir}/postgresql.conf.old
cat > ${pg_datadir}/postgresql.conf <<EOF
# 重要参数
#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------
listen_addresses = '*'
port = 5432
max_connections = 512
superuser_reserved_connections = 10
#max_locks_per_transaction = 64
track_commit_timestamp = on
wal_level = replica
wal_log_hints = on
wal_keep_segments = 128
max_wal_senders = 24
max_replication_slots = 16
password_encryption = md5
# $(expr $(free -m|grep Mem|awk '{print $2}') / 4)
shared_buffers = ${shared_buffers}
#huge_pages = try
work_mem = 4MB
maintenance_work_mem = ${maintenance_work_mem}
# 根据CPU核数来算，至少值为2   max(CPU核数/2,2)
# $(expr $(cat /proc/cpuinfo| grep "cpu cores"| uniq|awk '{print $4}')/2)
max_parallel_maintenance_workers = ${max_parallel_maintenance_workers}
# 根据CPU核数来算，至少值为2   max(CPU核数/2,2)
max_parallel_workers_per_gather = ${max_parallel_workers_per_gather}
#max_parallel_workers = max(DBInstanceClassCPU*3/4, 8)
max_parallel_workers = 8
temp_file_limit = 20GB
#vacuum_cost_delay = 20ms
#vacuum_cost_limit = 2000
bgwriter_lru_maxpages = 800
bgwriter_lru_multiplier = 5.0
# 最小256M，最大8G
min_wal_size = ${min_wal_size}
# 最小2G，最大16G
max_wal_size = ${max_wal_size}
wal_buffers = 16MB
wal_writer_delay = 20ms
#wal_writer_flush_after = 1MB
checkpoint_timeout = 15min
archive_mode = on
archive_timeout = 300
archive_command = 'pgbackrest --stanza=pro archive-push %p'
#vacuum_defer_cleanup_age = 0
hot_standby = on
max_standby_archive_delay = 10min
max_standby_streaming_delay = 3min
wal_receiver_status_interval = 1s
hot_standby_feedback = on
#wal_receiver_timeout = 60s
#max_logical_replication_workers = 8
# HDD:4   SSD:1.1
random_page_cost = ${random_page_cost}
# HDD:2  SSD:200 
effective_io_concurrency = 2
effective_cache_size = ${effective_cache_size}

## 时区相关
timezone = 'Asia/Shanghai'
log_timezone = 'Asia/Shanghai'

## 日志相关配置
log_destination = csvlog
logging_collector = on
log_truncate_on_rotation  = on
log_filename = 'postgresql-%d.log'
# 当天产生日志超出5G则覆盖重写，也可设置为0不覆盖
log_rotation_size = 500MB
log_rotation_age = 1d
log_checkpoints = on
log_lock_waits = on
log_statement = ddl
log_min_duration_statement = 1000

# 统计信息
track_io_timing = on
track_functions = pl
track_activity_query_size = 4096

# AUTOVACUUM
log_autovacuum_min_duration = 10s
autovacuum_work_mem = ${autovacuum_work_mem}
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_scale_factor = 0.08
autovacuum_analyze_scale_factor = 0.05
autovacuum_vacuum_cost_delay = -1
autovacuum_vacuum_cost_limit = -1

idle_in_transaction_session_timeout = 10min
shared_preload_libraries = 'pg_stat_statements'

#auto_explain.log_min_duration = -1
#auto_explain.log_analyze = off
#auto_explain.log_verbose = off
#auto_explain.log_timing = off
#auto_explain.log_nested_statements = t

pg_stat_statements.max = 5000
pg_stat_statements.track = top
pg_stat_statements.track_utility = off
pg_stat_statements.track_planning = off

#timescaledb.telemetry_level = 'off'
#timescaledb.max_background_workers = 16
EOF

    # 启动数据库
    systemctl start postgresql-12.service

    # 配置环境变量
    echo -e "
export PGDATA=${pg_datadir}
export LANG=en_US.utf8
export PGHOME=/usr/pgsql-12
export PATH=$PATH:$PGHOME/bin
export LD_LIBRARY_PATH=/usr/pgsql-12/lib" >> /home/postgres/.bash_profile
    source /home/postgres/.bash_profile
}


function pg_backup_pgbackrest(){
    # 创建pgbackrest相关目录
    mkdir -p -m 770 ${pgbackrest_log_dir}
    mkdir -p ${pgbackrest_config_dir}
    touch ${pgbackrest_config_dir}/pgbackrest.conf
    chmod 640 ${pgbackrest_config_dir}/pgbackrest.conf
    chown postgres:postgres ${pgbackrest_log_dir}
    chown postgres:postgres ${pgbackrest_config_dir}/pgbackrest.conf

    # 备份存放路径
    mkdir ${pg_backupdir}
    chmod 750 ${pg_backupdir}
    chown postgres:postgres ${pg_backupdir}

    # 拷贝已编译好的pgbackrest
    if [ ! -f "/usr/bin/pgbackrest" ]; then
        cp ${current_dir}/pgbackrest12 /usr/bin/pgbackrest
        chmod +x /usr/bin/pgbackrest
        chown postgres:postgres /usr/bin/pgbackrest
    fi

    # 配置pgbackrest
    echo -e "
[pro]
pg1-path=${pg_datadir}
pg1-port=${pg_port}

[global]
repo1-path=${pg_backupdir}
# 保留3个完整的备份
repo1-retention-full=3
# 备份快速启动
start-fast=y
# 可以启用并行来加快速度，但执行备份阶段一般不需要（因为可能CPU不足的话会影响数据库服务器性能），执行恢复阶段可以考虑打开（恢复阶段PG已关闭）
# process-max=3

[global:archive-push]
compress-level=3" > /etc/pgbackrest/pgbackrest.conf

    # 创建存储空间
    su - postgres -c "pgbackrest --stanza=pro --log-level-console=info stanza-create"

    # 检查配置
    su - postgres -c "pgbackrest --stanza=pro --log-level-console=info check"
}

function uninstall_all(){
    yum remove postgresql12 -y 
    rm -rf ${pg_dir}
    rm -rf ${pgbackrest_log_dir}
    rm -rf ${pgbackrest_config_dir}
}


system_disabe_selinux
pg_yum_install
pg_backup_pgbackrest


# 删除所有相关
# uninstall_all
