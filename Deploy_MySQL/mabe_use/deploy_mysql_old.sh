#!/bin/bash
set -e

SCRIPT_DIR=$(cd `dirname $0`; pwd)
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

# 系统初始化操作
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
	print_message "Note" "检查系统初始化信息..."
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

# 创建用户
create_user(){
  CREATE_USER=$1
  CREATE_PASSWORD=$2
  CREATE_USER_PRIVS=$3
  ./create_user.sh  $MYSQL_LINK_DIR/bin/mysql root "${INIT_PASSWORD}" "$MYSQL_PORT" "$SOCKET_DIR" "$CREATE_USER" "${CREATE_PASSWORD}" "${CREATE_USER_PRIVS}"
}

check_params_basic(){
  if [ ! $SCRIPT_DIR ] || [ ! $MYSQL_DATA_DIR ] || [ ! $MYSQL_PKG ] || [ ! $MYSQL_PORT ] || [ ! $MEMORY_ALLLOW_GB ] || [ ! ${INIT_PASSWORD} ] || [ ! $IPADDR ];then
    print_message "Error" "delply_mysql 指令参数不全，请检查 ./config/user.conf 文件"
    exit 1
  fi

  IP_IS_EXISTS=`ip -4 a|grep -w $IPADDR|wc -l`
  if [ $IP_IS_EXISTS -eq 0 ];then
    print_message "Error" "传入IP 与当前服务器IP不匹配，请检查 ./config/user.conf 文件中的IPADDR设置"
    exit 1
  fi
}

check_params_master(){
  if [ ! "$REPL_USER" ] || [ ! "${REPL_PASSWORD}" ] || [ ! "${REPL_PRIV}" ];then
    print_message "Error" "复制相关参数不全，请检查[REPL_USER、REPL_PASSWORD、REPL_PRIV]"
    exit 1
  fi
}

check_params_slave(){
  if [ ! "$REPL_USER" ] || [ ! "${REPL_PASSWORD}" ] ;then
    print_message "Error" "复制相关参数不全，请检查[REPL_USER、REPL_PASSWORD、]"
    exit 1
  fi
}

# 检查高可用复制参数
check_params_orchestrator(){
  if [ ! "$VIP" ] || [ ! "$NET_WORK_CARD_NAME" ] || [ ! "$ORCHESTRATOR_USER" ] || [ ! "$ORCHESTRATOR_PASSWORD" ] || [ ! "$ORCH_HTTP_USER" ] || [ ! "${ORCH_HTTP_PASSWORD}" ] || [ ! "$ORCHESTRATOR_RAFT_NODES" ];then
    print_message "Error" "复制相关参数不全，请检查[REPL_USER、REPL_PASSWORD、]"
    exit 1
  fi
}

check_ssh_without_password(){
  if [ $ORCHESTRATOR_RAFT_NODES ];then
    print_message "Note" "检测传入的集群IPS，值为:[$ORCHESTRATOR_RAFT_NODES]"
    OLD_IFS="$IFS"
    IFS=","
    ARR_NODES=($ORCHESTRATOR_RAFT_NODES)
    IFS="$OLD_IFS"
    
  fi
  
  print_message "Note" "进行hosts配置与免密配置检查..."
  for i in ${ARR_NODES[@]};
  do
    GET_HOSTS=`cat /etc/hosts |grep $i|awk '{print $2}'`
    if [ $GET_HOSTS ];then
      SSH_FREE_STATUS=`ssh $GET_HOSTS -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no "date" |wc -l`
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

single_install(){
  INSTALL_TYPE="single"
  MYCNF_DEFAULT=./config/$MYSQL_LARGE_VERSION/my.cnf.$INSTALL_TYPE
  cd $SCRIPT_DIR
  ${SCRIPT_DIR}/init_install_mysql.sh "$MYSQL_DATA_DIR" "$MYSQL_PKG" "$MYSQL_PORT" "$MEMORY_ALLLOW_GB" "${INIT_PASSWORD}" "$MYCNF_DEFAULT" "$IPADDR" 
}

master_install(){
  # 参数检查
  #check_params_master
  
  INSTALL_TYPE="master"
  MYCNF_DEFAULT=./config/$MYSQL_LARGE_VERSION/my.cnf.$INSTALL_TYPE
  cd $SCRIPT_DIR
  ${SCRIPT_DIR}/init_install_mysql.sh "$MYSQL_DATA_DIR" "$MYSQL_PKG" "$MYSQL_PORT" "$MEMORY_ALLLOW_GB" "${INIT_PASSWORD}" "$MYCNF_DEFAULT" "$IPADDR"
  # 创建复制用户
  create_user "$REPL_USER" "${REPL_PASSWORD}" "${REPL_PRIV}"
}

slave_install(){
  #check_params_slave

  INSTALL_TYPE="slave"
  MYCNF_DEFAULT=./config/$MYSQL_LARGE_VERSION/my.cnf.$INSTALL_TYPE
  cd $SCRIPT_DIR
  ${SCRIPT_DIR}/init_install_mysql.sh "$MYSQL_DATA_DIR" "$MYSQL_PKG" "$MYSQL_PORT" "$MEMORY_ALLLOW_GB" "${INIT_PASSWORD}" "$MYCNF_DEFAULT" "$IPADDR"
}

replica_install(){
  # 安装slave+change master
  slave_install
  cd $SCRIPT_DIR
  ${SCRIPT_DIR}/init_change_master.sh "$MYSQL_DATA_DIR" "root" ${INIT_PASSWORD} "$MYSQL_PORT" "$SOCKET_DIR" "$SOURCE_IPADDR" "$MYSQL_PORT" "$REPL_USER" ${REPL_PASSWORD} ${MYSQL_VERSION}
}

ha_tool_install(){
  #check_params_orchestrator
  #check_ssh_without_password
  INSTALL_TYPE=$1
  # 部署主实例，则创建组件监控用户
  if [ $INSTALL_TYPE = "ha2master" ];then 
    ORCH_PRIV="SUPER, PROCESS, REPLICATION SLAVE, RELOAD"
    create_user "$ORCHESTRATOR_USER" "${ORCHESTRATOR_PASSWORD}" "${ORCH_PRIV}"
    $MYSQL_LINK_DIR/bin/mysql -uroot -p"${INIT_PASSWORD}" -S ${SOCKET_DIR} -e "GRANT SELECT ON mysql.slave_master_info TO ${ORCHESTRATOR_USER}@'%'"
  fi
  # 配置安装高可用组件
  ${SCRIPT_DIR}/install_orchestrator.sh ${ORCHESTRATOR_USER} ${ORCHESTRATOR_PASSWORD} ${MYSQL_PORT} ${ORCH_HTTP_USER} ${ORCH_HTTP_PASSWORD} ${IPADDR} ${ORCHESTRATOR_RAFT_NODES} ${VIP} ${NET_WORK_CARD_NAME} ${IPADDR} ${SCRIPT_DIR} ${MYSQL_VERSION} ${SSH_PORT} ${ORCH_PORT}
    
  mv /tmp/warning_dingding.sh /usr/local/orchestrator/
  cp ${SCRIPT_DIR}/dingtalk_send /usr/local/orchestrator/
}

check_other_params(){
  # 检查钉钉相关
  if [ ${DINGDING_ALARM_STATUS} -eq 1 ];then
    if [ ! "${MSG_TITLE}" ] || [ ! "${DINGDING_URL}" ];then
      print_message "Error" "钉钉告警相关参数不全，请检查!"
      exit 1
    fi
  fi
#  # 检查邮件相关
#  if [ ${MAIL_ALARM_STATUS} -eq 1 ];then
#    if [ ! "${EMAIL_RECIVER}" ] || [ ! "${EMAIL_SENDER}" ] || [ ! "${EMAIL_USERNAME}" ] || [ ! "${EMAIL_PASSWORD}" ] || [ ! "${EMAIL_SMTPHOST}" ] || [ ! "${EMAIL_TITLE}" ];then
#      print_message "Error" "邮件告警相关参数不全，请检查!"
#      exit 1
#    fi
#    print_message "Note" "使用邮件告警,参数预检查..."
#    OPENSSL_CHECK=`rpm -qa|grep openssl-|wc -l`
#    if [ $OPENSSL_CHECK -eq 0 ];then
#      print_message "Error" "请先安装依赖 openssl 包!"
#      exit 1    
#    fi
#  fi
}

ding_test(){
  ${SCRIPT_DIR}/send_ding_msg.sh "钉钉连通性测试" "测试" "我是世界第一帅!\n\n 发送服务器:${IPADDR}"
  if [ "$?" = "0" ];then
    print_message "Note" "钉钉消息发送成功"
  else
    print_message "Error" "发送钉钉消息失败"
    exit 1
  fi
}
set_warning_script(){
  if [ ${DINGDING_SWITCH} -eq 1 ];then
    print_message "Note" "验证钉钉告警是否可用..."
    ding_test
  fi   
    cat > /tmp/warning_dingding.sh <<EOF
#!/bin/bash

OLD_MASTER=\$1
NEW_MASTER=\$2
LOCAL_HOST_IP='${IPADDR}'
#msg_title="钉钉消息通知"
HAPPEN_TIME=\`date "+%Y-%m-%d %H:%M:%S"\`

DINGDING_SWITCH=${DINGDING_SWITCH}
MSG_TITLE="数据库切换告警"
WEBHOOK_URL='${WEBHOOK_URL}'
SECRET='${SECRET}'
# 支持 text/markdown
SEND_TYPE="markdown"
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=""
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=""

SCRIPT_DIR=\$(cd \`dirname \$0\`; pwd)

## 打印
print_message(){
  TAG=\$1
  MSG=\$2
  if [[ \$1 = "Error" ]];then
    echo -e "\`date +'%F %T'\` [\\033[31m\$TAG\\033[0m] \$MSG"
  elif [[ \$1 = "Warning" ]];then
    echo -e "\`date +'%F %T'\` [\\033[34m\$TAG\\033[0m] \$MSG"
  else
    echo -e "\`date +'%F %T'\` [\\033[32m\$TAG\\033[0m] \$MSG"
  fi
}

# 钉钉信息发送
## \$1 通知/异常
## \$2 发送信息
dingding_note(){
  if [[ \${DINGDING_SWITCH} -eq 1 ]];then
    print_message "通知" "发送钉钉通知..."
    if [[ \$1 == "通知" ]]; then
      local color="#006600"
    else
      local color="#FF0033"
    fi
    local DING_MESSAGE="**[<font color=\${color}>\$1</font>]** \\n \\n--- \\n\$2"
    if [[ \${IS_AT_ALL} ]];then
      DING_STATUS=\`\${SCRIPT_DIR}/dingtalk_send -url "\${WEBHOOK_URL}" -secert "\${SECRET}" -title "\${MSG_TITLE}" -type "\${SEND_TYPE}" -msg "\${DING_MESSAGE}" -at_all\`
    elif [[ \${AT_MOBILES} ]];then
     DING_STATUS=\`\${SCRIPT_DIR}/dingtalk_send -url "\${WEBHOOK_URL}" -secert "\${SECRET}" -title "\${MSG_TITLE}" -type "\${SEND_TYPE}" -msg "\${DING_MESSAGE}" -at_mobiles \${AT_MOBILES}\`
    else
      DING_STATUS=\`\${SCRIPT_DIR}/dingtalk_send -url "\${WEBHOOK_URL}" -secert "\${SECRET}" -title "\${MSG_TITLE}" -type "\${SEND_TYPE}" -msg "\${DING_MESSAGE}"\`
    fi
    if [ "\${DING_STATUS}" = '{"errcode":0,"errmsg":"ok"}' ];then
      print_message "Note" "钉钉消息发送成功"
    else
      print_message "Error" "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \\"通知\\" \\"\${DING_MSG}\\""
      exit 1
    fi
    print_message "通知" "钉钉通知完成..."
  fi
}

check_switch_status(){
  if [ -f /tmp/orch.log ];then
    SWITCH_STATUS=\`tail -3 /tmp/orch.log |grep 'is moved to'|wc -l\`
    if [ \${SWITCH_STATUS} -eq 1 ];then
      SWITCH_STATUS_MSG='VIP切换成功'
    else
      SWITCH_STATUS_MSG='VIP切换失败,请检查!'
    fi
  else
    SWITCH_STATUS_MSG='不存在日志/tmp/orch.log,请检查!'
  fi
  if [ -f /tmp/recovery.log ];then
    SWITCH_MSG=\`tail -1 /tmp/recovery.log\`
  else
    SWITCH_MSG="不存在日志 /tmp/recovery.log,请检查!"
  fi
}

dingding_send(){
  if [[ \${DINGDING_SWITCH} -eq 1 ]];then
    local DING_MSG="\\n #### **<font color=#FF0033>发生高可用切换</font>** \\n* 原主IP：\${OLD_MASTER}\\n* 新主IP：\${NEW_MASTER}\\n* vip切换状态:\${SWITCH_STATUS_MSG} \\n* 执行切换操作服务器IP: \${LOCAL_HOST_IP}\\n* 切换信息:\${SWITCH_MSG} \\n*---\\n 发生时间:\\n \${HAPPEN_TIME}"
    dingding_note "异常" "\${DING_MSG}"
  else
    print_message "通知" "发生切换,但未配置钉钉告警."
  fi
}
  
check_switch_status
dingding_send
EOF

chmod +x /tmp/warning_dingding.sh
}

cleanup(){
  print_message "Note" "清理已部署MySQL环境..."
  if [ $MYSQL_PORT ];then
    IS_RUNNING=`ps -ef|grep mysqld|grep ${MYSQL_PORT}|grep defaults-file|wc -l`
    if [ ${IS_RUNNING} -eq 1 ];then
      print_message "Note" "停止MySQL..."
      systemctl stop mysqld${MYSQL_PORT}
    fi
      print_message "Note" "删除数据文件 ${MYSQL_DATA_DIR}/mysql${MYSQL_PORT}"
      rm -rf ${MYSQL_DATA_DIR}/mysql${MYSQL_PORT}
      print_message "Note" "删除环境变量文件 /etc/profile.d/mysql_set_env.sh"
      rm -f /etc/profile.d/mysql_set_env.sh
      print_message "Note" "删除systemctl启停服务 /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service"
      rm -f /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service
  else
    print_message "Error" "端口不存在,请检查端口..."
  fi
  
  IS_SOCKET=`ls /tmp/mysql.sock |grep mysql${MYSQL_PORT}|wc -l`
  if [ ${IS_SOCKET} -eq 1 ];then
    print_message "Note" "删除socket软链: /tmp/mysql.sock..."
    unlink /tmp/mysql.sock
  fi 
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
  VIP_IS_STATUS=`ip -4 a|grep ${VIP}|wc -l`
  if [ ${VIP_IS_STATUS} -eq 1 ];then
    print_message "Note" "卸载配置的VIP,VIP:${VIP}"
    ip addr del ${VIP} dev ${NET_WORK_CARD_NAME}
  fi
  print_message "Note" "清理完成"
}

before_install(){
  check_params_basic
  #check_other_params
  set_warning_script
  check_system_init
  if  [ "$1" = "master" ];then
    check_params_master
  fi
  if  [ "$1" = "slave" ];then
    check_params_slave   
  fi
  if  [ "$1" = "ha2master" ];then
    check_params_master
    check_params_orchestrator
    check_ssh_without_password
  fi
  if  [ "$1" = "ha2slave" ];then
    check_params_slave
    check_params_orchestrator
    check_ssh_without_password
  fi
}

#加载配置文件
source ${SCRIPT_DIR}/config/user.conf

BASE_DIR='/usr/local'
DATA_DIR=$MYSQL_DATA_DIR/mysql$MYSQL_PORT/data
SOCKET_DIR=$DATA_DIR/mysql.sock
MYSQL_LINK_DIR=$BASE_DIR/mysql
MYSQL_VERSION=`echo ${MYSQL_PKG##*/}|awk -F "-" '{print $2}'`
MYSQL_LARGE_VERSION=`echo ${MYSQL_VERSION%.*}`

if  [ "$1" = "single" ];then
  before_install $1
  single_install
elif  [ "$1" = "master" ];then
  before_install $1
  master_install
elif  [ "$1" = "slave" ];then
  before_install $1
  slave_install
elif  [ "$1" = "replica" ];then
  before_install $1
  replica_install
elif  [ "$1" = "ha2master" ];then
  # 添加vip
  IS_VIP=`arping -I ${NET_WORK_CARD_NAME} -f ${VIP} -c 1|grep "Unicast reply"|wc -l`
  VIP_IS_EXISTS=`ip -4 a|grep $VIP|wc -l`
  if [ $IS_VIP -gt 0 ] || [ $VIP_IS_EXISTS -gt 0 ];then
    print_message "Error" "vip [$VIP] 已被使用，请检查！"
    exit 1
  fi
  
  before_install $1
  master_install
  ha_tool_install "ha2master"
  print_message "Note" "设置vip [$VIP]。"
  ip addr add $VIP/32 dev $NET_WORK_CARD_NAME
  print_message "Note" "vip [$VIP] 已设置。"
  print_message "Note" "主节点安装完成。"	
elif  [ "$1" = "ha2slave" ];then
  before_install $1
  replica_install
  ha_tool_install "ha2slave"
  print_message "Note" "从节点安装完成。"
elif [ "$1" = "cleanup" ];then
    cleanup
else
  printf "Usage: bash 
    install_mysql.sh single     部署单机
    install_mysql.sh master     部署主节点,会安装半同步插件,且开启主节点相关参数
    install_mysql.sh slave      部署从节点,会安装半同步插件,且开启从节点相关参数
    install_mysql.sh replica    作为从库进行部署,需要主节点已部署,会作为从节点部署且建立好主从关系
    install_mysql.sh ha2master  高可用主节点部署,会同时部署 orch 高可用插件
    install_mysql.sh ha2slave   高可用从节点部署,会同时部署 orch 高可用插件
    install_mysql.sh cleanup    清空部署的相关信息
    "
  exit 1
fi
