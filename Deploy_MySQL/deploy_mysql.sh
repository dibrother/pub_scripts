#!/bin/bash
set -e

SCRIPT_DIR=$(cd `dirname $0`; pwd)
#加载配置文件
source ${SCRIPT_DIR}/config/user.conf
BASE_DIR='/usr/local'
DATA_DIR=$MYSQL_DATA_DIR/mysql$MYSQL_PORT/data
SOCKET_DIR=$DATA_DIR/mysql.sock
MYSQL_LINK_DIR=$BASE_DIR/mysql
MYSQL_VERSION=`echo ${MYSQL_PKG##*/}|awk -F "-" '{print $2}'`
MYSQL_LARGE_VERSION=`echo ${MYSQL_VERSION%.*}`

# 常量
INSTALL_TYPE_SINGLE="single"
INSTALL_TYPE_MASTER="master"
INSTALL_TYPE_SLAVE="slave"
## 打印
print_message(){
  TAG=$1
  MSG=$2
  if [[ $1 = "Error" ]];then
    echo -e "`date +'%F %T'` [\033[31m$TAG\033[0m] $MSG"
  elif [[ $1 = "Warning" ]];then
    echo -e "`date +'%F %T'` [\033[34m$TAG\033[0m] $MSG"
  else
    echo -e "`date +'%F %T'` [\033[32m$TAG\033[0m] $MSG"
  fi
}

# 进行系统初始化操作
function sys_init() {
    local timestamp=`date +%F-%T`
    mv /etc/sysctl.conf /etc/sysctl.conf.bak-$timestamp
    cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_tw_buckets = 55000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1100 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 200000
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 2097152
net.core.wmem_max = 2097152
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce=2
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
vm.swappiness = 0
kernel.sysrq = 1
vm.max_map_count = 262144
fs.inotify.max_user_instances = 8192
EOF
    sysctl -p
    echo "net.netfilter.nf_conntrack_max = 524288" >> /etc/sysctl.conf
    echo -e "root soft nofile 65535\nroot hard nofile 65535\n* soft nofile 65535\n* hard nofile 65535" >> /etc/security/limits.conf
    echo "DefaultLimitNOFILE=65535" >> /etc/systemd/system.conf
    systemctl daemon-reload
}

# 检查并设置系统初始化
check_system_init(){
	FIREWALLD_STATUS=`systemctl status firewalld|grep "active (running)"|wc -l`
	print_message "Note" "检查防火墙状态..."
	if [ $FIREWALLD_STATUS -gt 0 ];then
	  print_message "Warning" "防火墙状态为启用，将执行关闭防火墙..."
	  print_message "Warning" "关闭防火墙..."
	  systemctl stop firewalld
	  print_message "Warning" "取消防火墙开机自启..."
      systemctl disable firewalld
	fi
	
	print_message "Note" "检查 SELINUX 状态..."
	SELINUX_SATUS=`cat /etc/selinux/config |grep "SELINUX=disabled"|wc -l`
	if [ $SELINUX_SATUS -eq 0 ];then
	  print_message "Warning" "设置SELINUX为disabled..."
	  setenforce 0
      sed -i s"/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config
	fi

	print_message "Note" "检查初始化参数，如 nofile，nproc等..."
    INIT_STATUS=`cat /etc/security/limits.conf|grep soft| grep nofile|grep 65535|grep \*|wc -l`
	if [ $INIT_STATUS -eq 0 ];then
		print_message "Warning" "系统尚未进行初始化，进行系统初始化参数设置..."
		sys_init
	fi
}

# 检查MySQL安装所需基础参数
check_params_basic(){
  if [ ! $MYSQL_DATA_DIR ] || [ ! ${MYSQL_PKG} ] || [ ! ${MYSQL_PORT} ] || [ ! ${MEMORY_ALLLOW_GB} ] || [ ! ${INIT_PASSWORD} ] || [ ! ${IPADDR} ];then
    echo "$MYSQL_DATA_DIR  - ${MYSQL_PKG} - ${MYSQL_PORT} - ${MEMORY_ALLLOW_GB} - ${INIT_PASSWORD} - ${IPADDR}"
    print_message "Error" "MySQL安装所需基础参数设置不全，请检查 ./config/user.conf 文件"
    exit 1
  fi

  IP_IS_EXISTS=`ip -4 a|grep -w ${IPADDR}|wc -l`
  if [ ${IP_IS_EXISTS} -eq 0 ];then
    print_message "Error" "传入IP 与当前服务器IP不匹配，请检查 ./config/user.conf 文件中的IPADDR设置"
    exit 1
  fi
}

# 检查主从复制相关参数
check_params_with_repl(){
  if [ ! "${SOURCE_IPADDR}" ] || [ ! "${REPL_USER}" ] || [ ! "${REPL_PASSWORD}" ] || [ ! "${IP_SEGMENT}" ];then
    print_message "Error" "检查主从复制相关参数不全，请检查配置文件中[SOURCE_IPADDR、REPL_USER、REPL_PASSWORD、IP_SEGMENT]"
    exit 1
  fi
}

# 创建复制用户
create_user_for_repl(){
    $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e "
    CREATE USER ${REPL_USER}@'${IP_SEGMENT}' IDENTIFIED BY '${REPL_PASSWORD}';
    GRANT Replication client,Replication slave ON *.* TO ${REPL_USER}@'${IP_SEGMENT}';"
}

# 检查连接性
check_mysql_connect_with_tcp(){
  local CHECK_HOST=$1
  local CHECK_USER=$2
  local CHECK_PASSWORD=$3
  local CHECK_PORT=$4
  echo "${MYSQL_LINK_DIR}/bin/mysqladmin -h"${CHECK_HOST}" -u"${CHECK_USER}" -p"${CHECK_PASSWORD}" -P ${CHECK_PORT} ping"
  local CHECK_RESULT=`${MYSQL_LINK_DIR}/bin/mysqladmin -h"${CHECK_HOST}" -u"${CHECK_USER}" -p"${CHECK_PASSWORD}" -P ${CHECK_PORT} ping`
  if [[ $CHECK_RESULT != "mysqld is alive" ]];then
    print_message "Error" "MySQL无法连接,请检查!,内容:[-h"${CHECK_HOST}" -u"${CHECK_USER}" -P ${CHECK_PORT}]"
    exit 1    
  fi
}

# 在从库配置主从关系，并将从库设置为只读,设置半同步参数
change_master(){
  if [[ $MYSQL_VERSION > "8.0.25" ]];then
    $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e"RESET MASTER;CHANGE REPLICATION SOURCE TO SOURCE_HOST = '${SOURCE_IPADDR}',SOURCE_PORT = ${MYSQL_PORT},SOURCE_USER = '${REPL_USER}',SOURCE_PASSWORD = '${REPL_PASSWORD}',SOURCE_AUTO_POSITION = 1,MASTER_SSL = 1;START REPLICA;set global read_only=1;set global super_read_only=1;set global rpl_semi_sync_source_enabled=0;set global rpl_semi_sync_replica_enabled=1;"
    REPLICA_STATUS=`$MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e"show replica status\G"|grep -E "Replica_IO_Running:|Replica_SQL_Running:"|wc -l`
  else
    $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e"RESET MASTER;CHANGE MASTER TO MASTER_HOST = '${SOURCE_IPADDR}',MASTER_PORT = ${MYSQL_PORT},MASTER_USER = '${REPL_USER}',MASTER_PASSWORD = '${REPL_PASSWORD}',MASTER_AUTO_POSITION = 1;START SLAVE;set global read_only=1;set global super_read_only=1;set global rpl_semi_sync_master_enabled=0;set global rpl_semi_sync_slave_enabled=1;"
    REPLICA_STATUS=`$MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e"show slave status\G"|grep -E "Slave_IO_Running:|Slave_SQL_Running:"|wc -l`
  fi
    
  if [ $REPLICA_STATUS -eq 2 ];then
    print_message "Note" "主从关系建立成功"
  else
    print_message "Note" "主从关系建立失败,请检查"
    exit 1
  fi
}

# 安装MySQL
mysql_install(){
  INSTALL_TYPE="$1"
  MYCNF_DEFAULT=./config/$MYSQL_LARGE_VERSION/my.cnf.$INSTALL_TYPE
  cd $SCRIPT_DIR
  ${SCRIPT_DIR}/init_install_mysql.sh "$MYSQL_DATA_DIR" "$MYSQL_PKG" "$MYSQL_PORT" "$MEMORY_ALLLOW_GB" "${INIT_PASSWORD}" "$MYCNF_DEFAULT" "$IPADDR" 
}

cleanup_mysql(){
  local CLEAN_MYSQL_PORT=$1
  local CLEAN_DATA_DIR=$MYSQL_DATA_DIR/mysql$CLEAN_MYSQL_PORT
  if [ $CLEAN_MYSQL_PORT ];then
    IS_RUNNING=`ps -ef|grep mysqld|grep ${CLEAN_MYSQL_PORT}|grep defaults-file|wc -l`
    if [ ${IS_RUNNING} -eq 1 ];then
      print_message "Note" "停止MySQL..."
      systemctl stop mysqld${CLEAN_MYSQL_PORT}
    fi
      print_message "Note" "删除数据文件 ${CLEAN_DATA_DIR}"
      rm -rf ${CLEAN_DATA_DIR}
      print_message "Note" "删除环境变量文件 /etc/profile.d/mysql_set_env.sh"
      rm -f /etc/profile.d/mysql_set_env.sh
      print_message "Note" "删除systemctl启停服务 /usr/lib/systemd/system/mysqld${CLEAN_MYSQL_PORT}.service"
      rm -f /usr/lib/systemd/system/mysqld${CLEAN_MYSQL_PORT}.service
  else
    print_message "Error" "端口不存在,请检查端口..."
  fi

  IS_SOCKET=`ls /tmp/mysql.sock |grep mysql${CLEAN_MYSQL_PORT}|wc -l`
  if [ ${IS_SOCKET} -eq 1 ];then
    print_message "Note" "删除socket软链: /tmp/mysql.sock..."
    unlink /tmp/mysql.sock
  fi
  print_message "Note" "清理完成"
}

# 卸载HA 中间件
cleanup_ha(){
 ORCH_IS_INSTALL=`rpm -qa|grep orchestrator|wc -l`
  if [ ${ORCH_IS_INSTALL} -gt 0 ];then
    ORCH_IS_RUNNING=`ps -ef|grep orchestrator |grep -v grep|wc -l`
    if [ ${ORCH_IS_RUNNING} -eq 1 ];then
      print_message "Note" "停止高可用组件Orchestrator..."
      systemctl stop orchestrator
    fi

    print_message "Note" "卸载Orchestrator..."
    rpm -qa|grep orchestrator|xargs rpm -e
    print_message "Note" "删除Orchestrator配置目录:rm -rf /usr/local/orchestrator/"
    rm -rf /usr/local/orchestrator/
    print_message "Note" "删除Orchestrator数据目录:rm -rf /etc/orchestrator.conf.json "
    rm -f /etc/orchestrator.conf.json
    print_message "Note" "删除Orchestrator环境变量设置脚本:rm -f /etc/profile.d/orchestrator_set_env.sh"
    rm -f /etc/profile.d/orchestrator_set_env.sh
  fi
  
  REPLICATION_MANAGER_IS_INSTALL=`rpm -qa|grep replication-manager-|wc -l`
  if [ ${REPLICATION_MANAGER_IS_INSTALL} -gt 0 ];then
    REPLICATION_MANAGER_IS_RUNNING=`ps -ef|grep replication-manager- |grep -v grep|wc -l`
    if [ ${REPLICATION_MANAGER_IS_RUNNING} -eq 1 ];then
      print_message "Note" "停止高可用组件replication-manager..."
      systemctl stop replication-manager
    fi

    print_message "Note" "卸载replication-manager..."
    rpm -qa|grep replication-manager-|xargs rpm -e
    print_message "Note" "删除replication-manager相关目录..."
    rm -f /etc/init.d/replication-manager
    rm -rf /etc/replication-manager
    rm -f /etc/systemd/system/replication-manager.service
    rm -f /usr/bin/replication-manager-cli
    rm -f /usr/bin/replication-manager-osc
    rm -rf /usr/share/replication-manager
    rm -rf /var/lib/replication-manager/cluster.d
  fi

  VIP_IS_STATUS=`ip -4 a|grep ${VIP}|wc -l`
  if [ ${VIP_IS_STATUS} -eq 1 ];then
    print_message "Note" "卸载配置的VIP,VIP:${VIP}"
    ip addr del ${VIP} dev ${NET_WORK_CARD_NAME}
  fi 
}

# 高可用参数检查
check_ha_params(){
  if [ ! "${VIP}" ] || [ ! "${NET_WORK_CARD_NAME}" ] || [ ! "${HA_USER}" ] || [ ! "${HA_PASSWORD}" ] || [ ! "${HA_HTTP_USER}" ] || [ ! "${HA_HTTP_PASSWORD}" ] || [ ! "${HA_PORT}" ] || [ ! "${HA_NODES}" ] || [ ! "${SSH_PORT}" ];then
    print_message "Error" "高可用相关参数未配置,请检查!"
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

# 检查SSH连通性
check_ssh_without_password(){
  if [ $HA_NODES ];then
    print_message "Note" "检测传入的集群IPS，值为:[$HA_NODES]"
    OLD_IFS="$IFS"
    IFS=","
    ARR_NODES=($HA_NODES)
    IFS="$OLD_IFS"
    
  fi
  
  #print_message "Note" "进行hosts配置与免密配置检查..."
  for i in ${ARR_NODES[@]};
  do
    GET_HOSTS=`cat /etc/hosts |grep $i|awk '{print $2}'`
    if [ $GET_HOSTS ];then
      SSH_FREE_STATUS=`ssh -p${SSH_PORT} $GET_HOSTS -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no "date" |wc -l`
      if [ $SSH_FREE_STATUS -lt 1 ];then
        print_message "Error" "免密验证[$GET_HOSTS]失败,请检查免密配置!"
        exit
      fi
    else
      print_message "Error" "IP[$i]未配置hosts[需要配置为xx.xx.xx.xx test01],请检查!"
      exit 1
    fi
  done
}

# 创建高可用用户
create_user_for_ha(){
    $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e "
    CREATE USER '${HA_USER}'@'${IP_SEGMENT}' IDENTIFIED BY '${HA_PASSWORD}';
    GRANT SUPER, PROCESS, REPLICATION CLIENT,REPLICATION SLAVE, RELOAD ON *.* TO '${HA_USER}'@'${IP_SEGMENT}';
    GRANT SELECT ON mysql.* TO '${HA_USER}'@'${IP_SEGMENT}';
    GRANT SELECT ON performance_schema.* TO '${HA_USER}'@'${IP_SEGMENT}';"
}

# 设置主复制相关参数
set_master_variables(){
    if [[ $MYSQL_VERSION > "8.0.25" ]];then
      $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e "
      set global rpl_semi_sync_source_enabled = 1;
      set global super_read_only = 0;
      set global read_only = 0;"
    else
      $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e "
      set global rpl_semi_sync_master_enabled = 1;
      set global super_read_only = 0;
      set global read_only = 0;"
    fi
}

# 高可用部署-orchestrator
ha_install_orchestrator(){
  # 配置安装高可用组件
  echo "${SCRIPT_DIR}/install_orchestrator.sh ${HA_USER} ${HA_PASSWORD} ${MYSQL_PORT} ${HA_HTTP_USER} ${HA_HTTP_PASSWORD} ${IPADDR} ${HA_NODES} ${VIP} ${NET_WORK_CARD_NAME} ${IPADDR} ${SCRIPT_DIR} ${MYSQL_VERSION} ${SSH_PORT} ${HA_PORT}"
  ${SCRIPT_DIR}/install_orchestrator.sh ${HA_USER} ${HA_PASSWORD} ${MYSQL_PORT} ${HA_HTTP_USER} ${HA_HTTP_PASSWORD} ${IPADDR} ${HA_NODES} ${VIP} ${NET_WORK_CARD_NAME} ${IPADDR} ${SCRIPT_DIR} ${MYSQL_VERSION} ${SSH_PORT} ${HA_PORT}
      
}

# 高可用部署-replication-manager
ha_install_replication_manager(){
  LAST_NODE=`echo ${HA_NODES##*,}`
  if [ ${LAST_NODE} = ${IPADDR} ];then
    print_message "Note" "(从库)安装replication-manager高可用组件..."
    ${SCRIPT_DIR}/install_replication_manager.sh
  fi
}

# 钉钉消息发送

# MySQL单机安装或安装为slave配置参数(未建立好主从)
install_mysql_single_or_slave(){
  print_message "Note" "检查并设置系统初始化..."
  check_system_init
  print_message "Note" "检查MySQL安装所需基础参数"
  check_params_basic
  print_message "Note" "安装MySQL[$1]"
  mysql_install $1
}

# MySQL安装为master模式,会创建一个复制用户
install_mysql_master(){
  print_message "Note" "检查并设置系统初始化..."
  check_system_init
  print_message "Note" "检查MySQL安装所需基础参数"
  check_params_basic
  print_message "Note" "检查主从相关配置参数..."
  check_params_with_repl
  print_message "Note" "安装MySQL[$1]"
  mysql_install $1
  print_message "Note" "创建复制使用用户${REPL_USER}@'${IP_SEGMENT}'"
  create_user_for_repl 
  print_message "Note" "设置主库相关参数，[read_only 置为 0，半同步复制参数 rpl_semi_sync_source_enabled = 1]"
  set_master_variables
}


# MySQL安装为slave,并建立好主从关系
install_mysql_master_as_slave(){
  print_message "Note" "检查主从相关配置参数..."
  check_params_with_repl
  install_mysql_single_or_slave "slave"
  print_message "Note" "检查与主库账号能否连接..."
  check_mysql_connect_with_tcp ${SOURCE_IPADDR} ${REPL_USER} ${REPL_PASSWORD} ${MYSQL_PORT}
  print_message "Note" "建立主从关系..."
  change_master  
}

# 脚本入口
if [ "$1" = "single" ];then
  print_message "Note" "开始安装MySQL[$INSTALL_TYPE_SINGLE]"
  install_mysql_single_or_slave $INSTALL_TYPE_SINGLE
elif [ "$1" = "master" ];then
  print_message "Note" "开始安装MySQL[$INSTALL_TYPE_MASTER]"
  install_mysql_master $INSTALL_TYPE_MASTER
elif [ "$1" = "slave" ];then
  print_message "Note" "安装MySQL[$INSTALL_TYPE_SLAVE]"
  install_mysql_single_or_slave $INSTALL_TYPE_SLAVE
elif [ "$1" = "as-slave" ];then
  print_message "Note" "开始安装MySQL[$INSTALL_TYPE_SLAVE]"
  install_mysql_master_as_slave $INSTALL_TYPE_SLAVE
elif [ "$1" = "change-master" ];then
  print_message "Note" "检查MySQL安装所需基础参数"
  check_params_basic
  print_message "Note" "检查主从相关配置参数..."
  check_params_with_repl
  print_message "Note" "建立主从关系..."
  change_master
elif [ "$1" = "ha2master" ];then
  if [[ "$2" != "orch" ]] && [[ "$2" != "replm" ]];then
    print_message "Error" "请传入参数 orch 或 replm,如: ./deploy_mysql.sh ha2master orch"
    exit 1
  fi
  print_message "Note" "检查高可用配置参数..."
  check_ha_params
  print_message "Note" "进行hosts配置与免密配置检查..."
  check_ssh_without_password
  print_message "Note" "开始安装MySQL[$INSTALL_TYPE_MASTER]"
  install_mysql_master $INSTALL_TYPE_MASTER
  print_message "Note" "创建HA用户..."
  create_user_for_ha
  if [[ "$2" = "orch" ]];then
    print_message "Note" "安装HA插件-orchestrator"
    ha_install_orchestrator
  fi
  print_message "Note" "设置vip [$VIP]。"
  ip addr add $VIP/32 dev $NET_WORK_CARD_NAME
  print_message "Note" "vip [$VIP] 已设置。"
  print_message "Note" "主节点安装完成。"	
elif [ "$1" = "ha2slave" ];then
  if [[ "$2" = "orch" ]] || [[ "$2" = "replm" ]];then
     print_message "Note" "检查高可用配置参数..."
     check_ha_params
     print_message "Note" "进行hosts配置与免密配置检查..."
     check_ssh_without_password
     print_message "Note" "开始安装MySQL[$INSTALL_TYPE_SLAVE]"
     install_mysql_master_as_slave $INSTALL_TYPE_SLAVE
  else
    print_message "Error" "请传入参数 orch 或 replm,如: ./deploy_mysql.sh ha2slave orch"
    exit 1
  fi
  if [[ "$2" = "orch" ]];then
    print_message "Note" "安装HA插件[orchestrator]"
    ha_install_orchestrator
  else
    ha_install_replication_manager
  fi
elif [ "$1" = "cleanup" ];then
  if [ $2 ];then
    if [ "$2" = "all" ];then
      print_message "Note" "清理已部署MySQL环境,端口号[${MYSQL_PORT}]..."
      cleanup_mysql ${MYSQL_PORT}
      cleanup_ha
    else
      print_message "Note" "清理已部署MySQL环境,端口号[$2]..."
      cleanup_mysql $2
    fi
  else
    print_message "Error" "请传入需要清理的MySQL端口号!"
  fi
else
  printf "Usage: bash 
    deploy_mysql.sh single         	    部署单机
    deploy_mysql.sh master     		    部署主节点,会安装半同步插件,且开启主节点相关参数
    deploy_mysql.sh slave      		    部署从节点,会安装半同步插件,且开启从节点相关参数
    deploy_mysql.sh as-slave   		    作为从库进行部署,需要主节点已部署,会作为从节点部署且建立好主从关系
    deploy_mysql.sh change-master      	    与配置文件中的主实例建立主从关系,仅做了change master操作    
    deploy_mysql.sh ha2master [orch/replm]  高可用主节点部署,同时部署 orchestrator/replication-manager高可用插件
    deploy_mysql.sh ha2slave  [orch/replm]  高可用从节点部署,同时部署 orchestrator/replication-manager 高可用插件
    deploy_mysql.sh cleanup [3306]    	    传入端口号,清空部署的相关信息
    "
  exit 1
fi
