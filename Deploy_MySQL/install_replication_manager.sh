#!/bin/bash
set -e

BASE_DIR=/usr/local
SCRIPT_DIR=$(cd `dirname $0`; pwd)
# 加载配置文件信息
source ${SCRIPT_DIR}/config/user.conf
CLUSTER_NAME=${HA_CLUSTER_NAME:-"cluster1"}
# 传入MySQL程序的安装路径
MYSQL_UNCOMPRESS=`echo ${MYSQL_PKG##*/}|awk -F ".tar" '{print $1}'`
MYSQL_BIN_DIR=$BASE_DIR/$MYSQL_UNCOMPRESS/bin

## 打印
print_message(){
  TAG=$1
  MSG=$2
  if [[ $TAG = "Error" ]];then
    echo -e "`date +'%F %T'` [\033[31m$TAG\033[0m] $MSG"
  elif [[ $TAG = "Warning" ]];then
    echo -e "`date +'%F %T'` [\033[34m$TAG\033[0m] $MSG"
  else
    echo -e "`date +'%F %T'` [\033[32m$TAG\033[0m] $MSG"
  fi
}

# 检查已安装
check_already_install(){
 echo '' 
}

# 检查传入参数
check_params(){
  if [ ! $HA_USER ] || [ ! ${HA_PASSWORD} ] || [ ! $HA_NODES ];then
    print_message "Error" "replication-manager 需要的参数设置不全，请检查！"
    exit 1
  fi

  if [ $HA_NODES ];then
    print_message "Note" "检测传入的HA_NODES，值为:[$HA_NODES]"
    OLD_IFS="$IFS"
    IFS=","
    ArrNodes=($HA_NODES)
    IFS="$OLD_IFS" 
    if [ ${#ArrNodes[@]} -lt 2 ];then
       print_message "Error" "replication-manager 高可用组件必须有2节点及以上。"
       exit 1
    fi
  fi
}

# 安装 replication-manager
install_replication_manager(){
  IS_INSTALL=`rpm -qa|grep replication-manager-|wc -l`
  if [ $IS_INSTALL -gt 0 ];then
    print_message "Warning" "[$IPADDR]已安装replication-manager组件"
  else
    print_message "Note" "安装 replication-manager 组件 ..."
    yum localinstall -y $SCRIPT_DIR/soft/replication-manager*.rpm
  fi
}

# 配置 /etc/replication-manager/cluster.d/cluster1.toml
# 默认会选择HA_NODES的前两个作为优先切换实例
replication_manager_config_cluster(){
  OLD_IFS="$IFS"
  IFS=","
  arr=($HA_NODES)
  IFS="$OLD_IFS"

  i=0
  for s in ${arr[@]}
  do
    i=$((i+1))
    echo $s
    if [ ! $DB_SERVER_HOSTS ];then
      DB_SERVER_HOSTS="$s:${MYSQL_PORT}"
      DB_SERVER_PREFERED_MASTER="$s:${MYSQL_PORT}"
    else
      DB_SERVER_HOSTS="$DB_SERVER_HOSTS,$s:${MYSQL_PORT}"
    fi
    if [ $i -gt 1 ] && [ $i -lt ${#arr[@]} ] && [ ${#arr[@]} -gt 2 ];then
      DB_SERVER_PREFERED_MASTER="$DB_SERVER_PREFERED_MASTER,$s:${MYSQL_PORT}"
    fi
  done

  # sed 根据行号替换值
  sed -i 's/db-servers-hosts.*/db-servers-hosts = '\"${DB_SERVER_HOSTS}\"'/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/db-servers-prefered-master.*/db-servers-prefered-master = '\"${DB_SERVER_PREFERED_MASTER}\"'/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/db-servers-credential.*/db-servers-credential = '\"${HA_USER}:${HA_PASSWORD}\"'/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/replication-credential.*/replication-credential = '\"${REPL_USER}:${REPL_PASSWORD}\"'/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/backup-restic = .*/backup-restic = false/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/monitoring-scheduler = .*/monitoring-scheduler = false/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/failover-mode = .*/failover-mode = "automatic"/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/failover-pre-script = .*/failover-pre-script = "\/etc\/replication-manager\/script\/vip_down.sh"/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/failover-post-script = .*/failover-post-script = "\/etc\/replication-manager\/script\/vip_up.sh"/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/failover-time-limit = .*/failover-time-limit = 300/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/failover-at-sync = .*/failover-at-sync = true/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
  sed -i 's/switchover-at-sync = .*/switchover-at-sync = true/' /etc/replication-manager/cluster.d/${CLUSTER_NAME}.toml
}

# 配置 /etc/replication-manager/config.toml
replication_manager_config(){
  sed -i '/mail-.*=/s/^/#/g' /etc/replication-manager/config.toml
  sed -i '/alert-slack-.*=/s/^/#/g' /etc/replication-manager/config.toml
  sed -i 's%api-credentials = .*%api-credentials = '\"$(echo $HA_HTTP_USER):$(echo $HA_HTTP_PASSWORD)\"'%' /etc/replication-manager/config.toml
  sed -i 's%backup-mydumper-path =.*%backup-mydumper-path = '\"$(echo $MYSQL_BIN_DIR)/mydumper\"'%' /etc/replication-manager/config.toml
  sed -i 's%backup-myloader-path =.*%backup-myloader-path = '\"$(echo $MYSQL_BIN_DIR)/myloader\"'%' /etc/replication-manager/config.toml
  sed -i 's%backup-mysqlbinlog-path =.*%backup-mysqlbinlog-path = '\"$(echo $MYSQL_BIN_DIR)/mysqlbinlog\"'%' /etc/replication-manager/config.toml
  sed -i 's%backup-mysqldump-path =.*%backup-mysqldump-path = '\"$(echo $MYSQL_BIN_DIR)/mysqldump\"'%' /etc/replication-manager/config.toml
}

# 配置VIP漂移脚本
config_vip_drift_scripts(){
    mkdir -p /etc/replication-manager/script
    cp $SCRIPT_DIR/config/demo/vip_down.sh /etc/replication-manager/script
    cp $SCRIPT_DIR/config/demo/vip_up.sh /etc/replication-manager/script
    cp $SCRIPT_DIR/dingtalk_send /etc/replication-manager/script
    REPLICATION_SCRIPT_DIR="/etc/replication-manager/script"

    sed -i 's/mysql_user=.*/mysql_user='$(echo \'$HA_USER\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/mysql_password=.*/mysql_password='$(echo \'$HA_PASSWORD\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/interface=.*/interface='$(echo $NET_WORK_CARD_NAME)'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/vip=.*/vip='$(echo $VIP)'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/ssh_options=.*/ssh_options='$(echo \'-p$SSH_PORT\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/DINGDING_SWITCH=.*/DINGDING_SWITCH='$(echo $DINGDING_SWITCH)'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/MSG_TITLE=.*/MSG_TITLE='\'数据库切换告警\''/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's%WEBHOOK_URL=.*%WEBHOOK_URL='$(echo \'$WEBHOOK_URL\')'%' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/SECRET=.*/SECRET='$(echo \'$SECRET\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/SEND_TYPE=.*/SEND_TYPE='$(echo \'$SEND_TYPE\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/IS_AT_ALL=.*/IS_AT_ALL='$(echo \'$IS_AT_ALL\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh
    sed -i 's/AT_MOBILES=.*/AT_MOBILES='$(echo \'$AT_MOBILES\')'/' ${REPLICATION_SCRIPT_DIR}/vip_down.sh 

    sed -i 's/mysql_user=.*/mysql_user='$(echo \'$HA_USER\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/mysql_password=.*/mysql_password='$(echo \'$HA_PASSWORD\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/interface=.*/interface='$(echo $NET_WORK_CARD_NAME)'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/vip=.*/vip='$(echo $VIP)'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/ssh_options=.*/ssh_options='$(echo \'-p$SSH_PORT\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/DINGDING_SWITCH=.*/DINGDING_SWITCH='$(echo $DINGDING_SWITCH)'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/MSG_TITLE=.*/MSG_TITLE='\'数据库切换告警\''/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's%WEBHOOK_URL=.*%WEBHOOK_URL='$(echo \'$WEBHOOK_URL\')'%' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/SECRET=.*/SECRET='$(echo \'$SECRET\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/SEND_TYPE=.*/SEND_TYPE='$(echo \'$SEND_TYPE\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/IS_AT_ALL=.*/IS_AT_ALL='$(echo \'$IS_AT_ALL\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh
    sed -i 's/AT_MOBILES=.*/AT_MOBILES='$(echo \'$AT_MOBILES\')'/' ${REPLICATION_SCRIPT_DIR}/vip_up.sh   

    chmod +x /etc/replication-manager/script/*
}

# 清除
clean_up_replication_manager(){
  rpm -e replication-manager-client-2.2.31-1.x86_64 replication-manager-osc-2.2.31-1.x86_64 && rm -rf /etc/replication-manager
}

# 启动
start_replication_manager(){
    systemctl start replication-manager
    systemctl status replication-manager
}

print_message "Note" "检查传入参数 ..."
check_params
print_message "Note" "安装replication_manager包 ..."
install_replication_manager
print_message "Note" "配置集群参数 ..."
replication_manager_config_cluster
print_message "Note" "配置服务参数 ..."
replication_manager_config
print_message "Note" "更改vip相关 ..."
config_vip_drift_scripts
print_message "Note" "启动replication服务 ..."
start_replication_manager
