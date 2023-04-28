#!/bin/bash
set -e

# 获取脚本路径
current_dir=$(cd $(dirname $0); pwd)
# 导入公共方法
source ${current_dir}/common.sh
# 导入配置文件
source ${current_dir}/config.cnf

# pgbackrest 相关目录
pgbackrest_log_dir=/var/log/pgbackrest
pgbackrest_config_dir=/etc/pgbackrest
pgbackrest_name=pgbackrest12

# 默认yum安装路径为，不需要改动
pg_home=/usr/pgsql-12

# 关闭 selinux
function system_disabe_selinux(){
    set +e
    setenforce 0
    set -e
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    systemctl disable firewalld.service
    systemctl stop firewalld.service
}

# 挂载本地yum源
function yum_mount_local(){
tar zxf ${current_dir}/pglocal_yum.tar.gz
mv ${current_dir}/pglocal_yum /tmp/

cat > /etc/yum.repos.d/pglocal_yum.repo <<EOF
[local]
name=pglocal_yum
baseurl=file:///tmp/pglocal_yum
gpgcheck=0
enabled=1
EOF

}

# yum 安装 postgresql
function pg_yum_install(){
    set +e
    comm_is_user_exists "postgres"
    if [ $? -eq 0 ];then
        useradd postgres
        echo 'postgres' | passwd -f --stdin postgres
    fi
    set -e
    yum install -y postgresql12-server postgresql12-contrib
}

# 创建数据目录
function pg_mkdir_data(){
    # 数据目录
    mkdir -p ${pg_dir}/data
    chown -R postgres:postgres ${pg_dir}/data
    chmod 700 ${pg_dir}/data
    # 更改数据目录
    sed -i 's#^Environment=PGDATA.*#Environment=PGDATA='${pg_datadir}'/#g' /usr/lib/systemd/system/postgresql-12.service
    systemctl daemon-reload
}

function pg_init(){
    # 初始化
    ${pg_home}/bin/postgresql-12-setup initdb
}   

function pg_set_config_hba(){
# 放开访问权限
    sed -i '87i host    all             all             0.0.0.0/0               md5' ${pg_datadir}/pg_hba.conf
}

# 获取动态参数值
function pg_get_config_dynamic_parameter(){
    shared_buffers="$(expr $(free -m|grep Mem|awk '{print $2}') / 4)MB"
    maintenance_work_mem="$(expr $(free -m|grep Mem|awk '{print $2}') / 16)MB"
    effective_cache_size="$(expr $(free -m|grep Mem|awk '{print $2}') / 2)MB"
    cpu_core=$(expr $(nproc) / 2)
    free_mem=$(free -m|grep Mem|awk '{print $2}')
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
        max_wal_size='2GB'
    elif [ ${max_wal_size} -gt 16384 ];then
        max_wal_size='16GB'
    else
        max_wal_size="${max_wal_size}MB"
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
}

# 配置 postgresql.conf
function pg_set_config_postgresql(){   
    mv ${pg_datadir}/postgresql.conf  ${pg_datadir}/postgresql.conf.old
cat > ${pg_datadir}/postgresql.conf <<EOF
# 重要参数
#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------
listen_addresses = '*'
port = ${pg_port}
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
}

# 配置PG环境变量
function pg_set_env(){
    echo -e "
export PGDATA=${pg_datadir}
export LANG=en_US.utf8
export PGHOME=$pg_home
export PATH=\$PATH:\$PGHOME/bin
export LD_LIBRARY_PATH=$PGHOME/lib" >> /home/postgres/.bash_profile
    source /home/postgres/.bash_profile
}

# 配置备份归档工具
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
        cp ${current_dir}/${pgbackrest_name} /usr/bin/pgbackrest
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

}

# 创建存储空间
function pg_backup_pgbackrest_stanza_create(){
    local check_master_or_slave=$(su - postgres -c "psql -c 'select pg_is_in_recovery();'"|grep t|wc -l)
    if [ $check_master_or_slave -eq 0 ];then
        # 创建存储空间
        su - postgres -c "pgbackrest --stanza=pro --log-level-console=info stanza-create"
        # 检查配置
        su - postgres -c "pgbackrest --stanza=pro --log-level-console=info check"
    else
        comm_print_note "当前实例为从库，无需创建备份空间。"
    fi
}

# 配置postgres用户sudo免密
function system_set_postgres_sudo_nopass(){
    local check_value=$(cat /etc/sudoers|grep postgres|grep /usr/sbin/ip|wc -l)
    if [ $check_value -eq 0 ];then
        sed -i '101i postgres ALL=(root) NOPASSWD: /usr/sbin/ip'  /etc/sudoers
    fi
}

# 安装ETCD
## ETCD_NAME: 默认设置为 etcd[IP最后一组值]
function etcd_yum_install(){
    comm_print_note "使用yum安装ETCD"
    yum install -y gcc python-devel epel-release
    yum install -y etcd

    comm_print_note "授权etcd数据目录"
    mkdir -p ${pg_dir}/etcd
    chown etcd:etcd -R ${pg_dir}/etcd

    local etcd_name="etcd$(echo ${local_ip}|awk -F . '{print $4}')"

    comm_print_note "设置etcd集群配置文件"
    local etcd_initial_cluster=''
    local array=(${etcd_cluster_ip//,/ })
    local num=0
    for ip in ${array[@]};
    do
        local ename="etcd$(echo ${ip}|awk -F . '{print $4}')"
        local ecluster="${ename}=http://${ip}:${etcd_cluster_port}"
        if [ $num -eq 0 ];then
            etcd_initial_cluster=${ecluster}
        else
            etcd_initial_cluster="${etcd_initial_cluster},${ecluster}"
        fi
        let num=num+1
    done

    cat > /etc/etcd/etcd.conf << EOF
ETCD_DATA_DIR="${pg_dir}/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://${local_ip}:${etcd_cluster_port}"
ETCD_LISTEN_CLIENT_URLS="http://localhost:${ectd_client_port},http://${local_ip}:${ectd_client_port}"
ETCD_NAME="${etcd_name}"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${local_ip}:${etcd_cluster_port}"
ETCD_ADVERTISE_CLIENT_URLS="http://${local_ip}:2379"
ETCD_INITIAL_CLUSTER="${etcd_initial_cluster}"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

    # 启动并查看
    comm_print_note "启动etcd...，若为首个启动会等待其他加入后完成启动...因此需要同步安装组成集群的其他的etcd"
    systemctl start etcd
    systemctl status etcd

    comm_print_note "配置 etcd 开机自启"
    systemctl enable etcd

    comm_print_note "查看list与cluster 状态"
    sleep 2
    etcdctl member list
    etcdctl cluster-health
}

# 安装patroni
function patroni_yum_install(){
    yum install -y gcc python-pip python-psycopg2 python-devel python3
    yum install -y patroni-etcd
}

# 配置patroni配置文件
function patroni_set_config(){

    mkdir -p ${pg_dir}/patroni/{log,bin}
    chown -R postgres.postgres ${pg_dir}/patroni

    local pg_name="pg$(echo ${local_ip}|awk -F . '{print $4}')"
    local timezone='Asia/Shanghai'
    local array=(${etcd_cluster_ip//,/ })
    cat > /etc/patroni/patroni.yml << EOF
scope: pgsql
namespace: ${pg_dir}/patroni
name: ${pg_name}

log:
  level: INFO                           #  NOTEST|DEBUG|INFO|WARNING|ERROR|CRITICAL
  dir: ${pg_dir}/patroni/log            #  patroni log dir
  file_size: 33554432                   #  32MB log triggers log rotation
  file_num: 10                          #  keep at most 10x32MB = 320M log
  dateformat: '%Y-%m-%d %H:%M:%S %z'    #  IMPORTANT: discard milli timestamp
  format: '%(asctime)s %(levelname)s: %(message)s'

restapi:
  listen: 0.0.0.0:8000
  connect_address: ${local_ip}:8000

etcd3:
  hosts: 
  - ${array[0]}:${ectd_client_port}
  - ${array[1]}:${ectd_client_port}
  - ${array[2]}:${ectd_client_port}

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    primary_start_timeout: 30
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        listen_addresses: '*'
        port: ${pg_port}
        max_connections: 512
        superuser_reserved_connections: 10
        track_commit_timestamp: on
        wal_level: replica
        wal_log_hints: on
        wal_keep_segments: 128
        max_wal_senders: 24
        max_replication_slots: 16
        password_encryption: md5
        shared_buffers: ${shared_buffers}
        work_mem: 4MB
        maintenance_work_mem: ${maintenance_work_mem}
        # 根据CPU核数来算，至少值为2   max(CPU核数/2,2)
        max_parallel_maintenance_workers: ${max_parallel_maintenance_workers}
        # 根据CPU核数来算，至少值为2   max(CPU核数/2,2)
        max_parallel_workers_per_gather: ${max_parallel_workers_per_gather}
        #max_parallel_workers: max(DBInstanceClassCPU*3/4, 8)
        max_parallel_workers: 8
        temp_file_limit: 20GB
        #vacuum_cost_delay: 20ms
        #vacuum_cost_limit: 2000
        bgwriter_lru_maxpages: 800
        bgwriter_lru_multiplier: 5.0
        # 最小256M，最大8G
        min_wal_size: ${min_wal_size}
        # 最小2G，最大16G
        max_wal_size: ${max_wal_size}
        wal_buffers: 16MB
        wal_writer_delay: 20ms
        #wal_writer_flush_after: 1MB
        checkpoint_timeout: 15min
        archive_mode: on
        archive_timeout: 300
        archive_command: 'pgbackrest --stanza=pro archive-push %p'
        #vacuum_defer_cleanup_age: 0
        hot_standby: on
        max_standby_archive_delay: 10min
        max_standby_streaming_delay: 3min
        wal_receiver_status_interval: 1s
        hot_standby_feedback: on
        #wal_receiver_timeout: 60s
        #max_logical_replication_workers: 8
        # HDD:4   SSD:1.1
        random_page_cost: ${random_page_cost}
        # HDD:2  SSD:200 
        effective_io_concurrency: 2
        effective_cache_size: ${effective_cache_size}
        
        ## 时区相关
        timezone: '${timezone}'
        log_timezone: '${timezone}'
        
        ## 日志相关配置
        log_destination: csvlog
        logging_collector: on
        log_truncate_on_rotation : on
        log_filename: 'postgresql-%d.log'
        # 当天产生日志超出5G则覆盖重写，也可设置为0不覆盖
        log_rotation_size: 500MB
        log_rotation_age: 1d
        log_checkpoints: on
        log_lock_waits: on
        log_statement: ddl
        log_min_duration_statement: 1000
        
        # 统计信息
        track_io_timing: on
        track_functions: pl
        track_activity_query_size: 4096
        
        # AUTOVACUUM
        log_autovacuum_min_duration: 10s
        autovacuum_work_mem: ${autovacuum_work_mem}
        autovacuum_max_workers: 3
        autovacuum_naptime: 1min
        autovacuum_vacuum_scale_factor: 0.08
        autovacuum_analyze_scale_factor: 0.05
        autovacuum_vacuum_cost_delay: -1
        autovacuum_vacuum_cost_limit: -1
        
        idle_in_transaction_session_timeout: 10min
        shared_preload_libraries: 'pg_stat_statements'
        
        #auto_explain.log_min_duration: -1
        #auto_explain.log_analyze: off
        #auto_explain.log_verbose: off
        #auto_explain.log_timing: off
        #auto_explain.log_nested_statements: t
        
        pg_stat_statements.max: 5000
        pg_stat_statements.track: top
        pg_stat_statements.track_utility: off
        pg_stat_statements.track_planning: off

  initdb:
  - encoding: UTF8
  - locale: C
  - lc-ctype: en_US.UTF-8

  pg_hba:
  - local   all             all                                     peer
  - host    all             all             127.0.0.1/32            ident
  - host    all             all             0.0.0.0/0               md5
  - local   replication     all                                     peer
  - host    replication     all             127.0.0.1/32            ident
  - host    replication     all            0.0.0.0/0                md5

postgresql:
  listen: 0.0.0.0:${pg_port}
  connect_address: ${local_ip}:${pg_port}
  data_dir: ${pg_datadir}
  bin_dir: ${pg_home}/bin

  authentication:
    replication:
      username: repl
      password: "123456"
    superuser:
      username: postgres
      password: "123456"
    rewind:
      username: postgres
      password: "123456"
    basebackup:
      #max-rate: '100M'
      checkpoint: 'fast'

  #------------------------------------------------------------#
  # how to react to database operations
  #------------------------------------------------------------#
  # event callback script log: /pg/log/patroni/callback.log
  callbacks:
    on_start: ${pg_dir}/patroni/bin/patroni_switch_vip.sh
    on_stop: ${pg_dir}/patroni/bin/patroni_switch_vip.sh
    on_reload: ${pg_dir}/patroni/bin/patroni_switch_vip.sh
    on_restart: ${pg_dir}/patroni/bin/patroni_switch_vip.sh
    on_role_change: ${pg_dir}/patroni/bin/patroni_switch_vip.sh

  # rewind policy: data checksum should be enabled before using rewind
  use_pg_rewind: true
  remove_data_directory_on_rewind_failure: true
  remove_data_directory_on_diverged_timelines: false
  
  create_replica_methods:
    - basebackup
  basebackup:
    - max-rate: '1000M'
    - checkpoint: fast
    - verbose
    - progress
  pgbackrest:
    command: /usr/bin/pgbackrest --stanza=pro --delta restore
    keep_data: true
    no_params: true
    no_leader: true
    no_leader: true

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF
}

# 生成vip切换脚本
function patroni_config_switch_vip(){
    local vip=${vip}
    local inf=$(ip addr show |grep ${local_ip}|awk '{print $NF}')

    cat > ${pg_dir}/patroni/bin/patroni_switch_vip.sh << EOF
#!/bin/bash

readonly OPERATION=\$1
readonly ROLE=\$2
readonly SCOPE=\$3

VIP=$vip
INF=$inf

# 检查 VIP 是否已存在[0：不存在 1:已存在]
check_vip_exists(){
  local chk_value=\$(sudo ip addr show dev \${INF} to \${VIP})
  if [ -n "\$chk_value" ];then
    return 1
  else
    return 0
  fi
}

# arping检查 VIP 是否已被占用[0：未占用 1:已占有]
check_vip_arp(){
  sudo arping -c 1 -I \${INF} \${VIP}
  if [ \$? -eq 0 ];then
    return 1
  else
    return 0
  fi
}

# 添加 VIP
cmd_vip_add(){
  if check_vip_exists && check_vip_arp;then
    sudo ip addr add  \${VIP} dev \${INF}
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP \${VIP} added"
  else
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP \${VIP} already be used,please check!"
  fi
}

# 删除 VIP
cmd_vip_del(){
  if ! check_vip_exists;then
    sudo ip addr del \${VIP}/32 dev \${INF}
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP \${VIP} removed"
  else
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP \${VIP} not exists,please check!"
  fi
}

echo "$(date "+%Y-%m-%d %H:%M:%S %z") This is patroni callback \$OPERATION \$ROLE $SCOPE"

case \$OPERATION in
 on_stop)
 cmd_vip_del
 ;;

 on_start | on_restart | on_role_change)
 if [[ \$ROLE == 'master' || \$ROLE == 'standby_leader' ]]; then
   cmd_vip_add 
 else
   cmd_vip_del
 fi
 ;;
 *)
 usage
 ;;
esac
EOF

    chown postgres.postgres ${pg_dir}/patroni/bin/patroni_switch_vip.sh
    chmod +x ${pg_dir}/patroni/bin/patroni_switch_vip.sh
}

# 配置 patroni 环境变量
function patroni_set_env(){
    echo "export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml" >> /home/postgres/.bash_profile
}

# 打印 patroni 状态
function patroni_status_print(){
    systemctl status patroni
    patronictl -c /etc/patroni/patroni.yml list 
}

############################################################################
# 安装单机版PG
function pg_install_single(){
    comm_print_note "禁用Selinux"
    system_disabe_selinux
    comm_print_note "挂载本地yum源"
    yum_mount_local
    comm_print_note "安装postgresql"
    pg_yum_install
    comm_print_note "创建PG数据目录"
    pg_mkdir_data
    comm_print_note "PG初始化"
    pg_init
    comm_print_note "配置hba.conf"
    pg_set_config_hba
    comm_print_note "配置postgresql.conf"
    pg_get_config_dynamic_parameter
    pg_set_config_postgresql
    comm_print_note "配置PG环境变量"
    pg_set_env
    comm_print_note "启动PG"
    systemctl start postgresql-12.service
    comm_print_note "安装配置pgbackrest"
    pg_backup_pgbackrest
    comm_print_note "创建pgbackrest存储空间"
    pg_backup_pgbackrest_stanza_create
    comm_print_note "安装完成"
}


# 安装PG高可用
function pg_install_ha(){
    comm_print_note "安装postgresql"
    pg_yum_install
    comm_print_note "创建PG数据目录"
    pg_mkdir_data
    comm_print_note "配置PG环境变量"
    pg_set_env
    comm_print_note "postgres用户配置免密"
    system_set_postgres_sudo_nopass
    comm_print_note "安装patroni"
    patroni_yum_install
    comm_print_note "设置patroni配置文件"
    pg_get_config_dynamic_parameter
    patroni_set_config
    comm_print_note "生成VIP切换脚本"
    patroni_config_switch_vip
    comm_print_note "配置patroni环境变量"
    patroni_set_env
    comm_print_note "启动patroni并查看状态"
    systemctl start patroni
    sleep 3
    patroni_status_print
    comm_print_note "安装配置pgbackrest"
    pg_backup_pgbackrest
    comm_print_note "创建pgbackrest存储空间"
    pg_backup_pgbackrest_stanza_create
    comm_print_note "安装完成"
}

# 卸载ETCD
function uninstall_etcd(){
    comm_print_note "卸载etcd"
    yum remove etcd -y 
    comm_print_note "删除etcd相关目录  ${pg_dir}/etcd"
    rm -rf ${pg_dir}/etcd
    rm -rf /var/lib/etcd
}

# 卸载PG
function uninstall_pg(){
    comm_print_note "卸载postgresql12"
    yum remove postgresql12 -y 
    comm_print_note "删除数据目录： ${pg_datadir}"
    rm -rf ${pg_datadir}
    comm_print_note "卸载patroni"
    yum remove patroni -y 
    rm -rf ${pg_dir}/patroni /etc/patroni
    comm_print_note "删除postgres用户"
    userdel postgres
    comm_print_note "卸载pgbsackrest"
    uninstall_pgbackrest
}

# 卸载部署的所有组件
function uninstall_all(){
    rm -rf /tmp/pglocal_yum/
    comm_print_note "卸载postgresql12"
    yum remove postgresql12 -y 
    comm_print_note "删除数据目录： ${pg_datadir} |  ${pgbackrest_log_dir}  |  ${pgbackrest_config_dir}"
    rm -rf ${pg_datadir}
    comm_print_note "卸载patroni"
    yum remove patroni -y 
    rm -rf ${pg_dir}/patroni /etc/patroni
    comm_print_note "卸载etcd"
    yum remove etcd -y 
    comm_print_note "删除etcd相关目录  ${pg_dir}/etcd"
    rm -rf ${pg_dir}/etcd
    rm -rf /var/lib/etcd
    comm_print_note "删除postgres用户"
    userdel postgres
    comm_print_note "卸载删除pgbackrest"
    uninstall_pgbackrest
}

# 卸载pgbackrest，同步会删除文件，也就是删除本机上的所有备份
function uninstall_pgbackrest(){
    comm_print_note "卸载pgbackrest"
    rm -f /user/bin/pgbackrests
    comm_print_note "删除数据目录： ${pgbackrest_log_dir} |  ${pg_backupdir}  |  ${pgbackrest_config_dir} | /tmp/pgbackrest"
    rm -rf ${pgbackrest_log_dir} ${pg_backupdir} ${pgbackrest_config_dir} /tmp/pgbackrest
}


# 使用说明
usage () {
        cat <<EOF
Usage: $0 [OPTIONS]
  single                 安装单机版PG
  ha                     安装HA的PG，使用patroni组件
  etcd                   安装ETCD，ha版的
  clearall               清除部署PG相关的所有中间件与环境信息
  clear_etcd             清除 etcd 相关环境
  clear_pg               清除 PG 相关环境
EOF
exit
}

# main 入口
command="${1}"
case "${command}" in
    "single" )
        comm_print_note "安装单机版PG"
	    pg_install_single
    ;;
    "ha" )
        comm_print_note "安装HA版PG"
	    pg_install_ha
    ;;
    "etcd" )
        comm_print_note "禁用Selinux"
        system_disabe_selinux
        comm_print_note "挂载本地yum源"
        yum_mount_local
	    comm_print_note "安装ETCD"
        etcd_yum_install
    ;;
    "clearall" )  
	    comm_print_note "清除部署PG的所有中间件与环境"
        uninstall_all
    ;;
    "clear_etcd" )  
	    comm_print_note "清除 etcd 相关环境"
        uninstall_etcd
    ;;
    "clear_pg" )  
	    comm_print_note "清除 PG 相关环境"
        uninstall_pg
    ;;
    * )
        usage
    ;;
esac