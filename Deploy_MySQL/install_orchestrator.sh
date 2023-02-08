#!/bin/bash
set -e
SCRIPT_DIR=$(cd `dirname $0`; pwd)
#加载配置文件
source ${SCRIPT_DIR}/config/user.conf
###
# ./install_orchestrator.sh orch 123456 3312 orch 123456 192.168.66.161 192.168.66.161,192.168.66.162,192.168.66.163 192.168.66.111 ens33 192.168.66.161 /opt/installMysql 8.0 22 3000
############# orchestrator 相关参数 ###################
MySQLTopologyUser=$1
MySQLTopologyPassword=$2
DefaultInstancePort=$3
HTTPAuthUser=$4
HTTPAuthPassword=$5
RaftBind=$6
RaftNodes=$7
Vip=${8}
NetworkCardName=${9}
CurrentIP=${10}
LocalRpmDir=${11}
MYSQL_VERSION=${12}
SSH_PORT=${13}
ORCH_PORT=${14}

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

# 检查传入参数
check_params(){
  if [ ! $MySQLTopologyUser ] || [ ! ${MySQLTopologyPassword} ] || [ ! $DefaultInstancePort ] || [ ! $HTTPAuthUser ] || [ ! ${HTTPAuthPassword} ] || [ ! $Vip ] || [ ! $NetworkCardName ] || [ ! $CurrentIP ] || [ ! $LocalRpmDir ] || [ ! $ORCH_PORT ];then
    echo "MySQLTopologyUser:$MySQLTopologyUser"
    echo "MySQLTopologyUser:$MySQLTopologyPassword"
    echo "MySQLTopologyUser:$DefaultInstancePort"
    echo "MySQLTopologyUser:$HTTPAuthUser"
    echo "HTTPAuthPassword:${HTTPAuthPassword}"
    echo "Vip:$Vip"
    echo "Vip:$NetworkCardName"
    echo "Vip:$CurrentIP"
    echo "Vip:$LocalRpmDir"
    echo "Vip:$ORCH_PORT"
    print_message "Error" "orchestrator 传入指令参数不全，请检查"
    exit 1
  fi

  if [ $RaftNodes ];then
    print_message "Note" "检测传入的RaftNodes，值为:[$RaftNodes]"
    OLD_IFS="$IFS"
    IFS=","
    ArrNodes=($RaftNodes)
    IFS="$OLD_IFS" 
    if [ ${#ArrNodes[@]} -lt 3 ];then
       print_message "Error" "组件高可用必须有3节点以上。"
    fi
  fi
}

install_orchestrator(){
  ORCH_IS_INSTALL=`rpm -qa|grep orchestrator-3.2.6|wc -l`
  if [ $ORCH_IS_INSTALL -gt 0 ];then
    print_message "Warning" "[$CurrentIP]已安装orchestrator组件"
  else
    print_message "Note" "安装 orchestrator 所需依赖包  jq ..."
    ONIGURUMA_STATUS=`rpm -qa|grep oniguruma-6.8.2-1.el7|wc -l`
    JQ_STATUS=`rpm -qa|grep jq-1.6-2.el7|wc -l`
    if [ $ONIGURUMA_STATUS -eq 0 ];then
      rpm -ivh ./soft/oniguruma-6.8.2-1.el7.x86_64.rpm
    fi
    if [ $JQ_STATUS -eq 0 ];then
      rpm -ivh ./soft/jq-1.6-2.el7.x86_64.rpm
    fi
    print_message "Note" "安装orchestrator组件..."
    yum localinstall -y $LocalRpmDir/soft/orchestrator*.rpm
  fi
}

add_orch_conf(){
print_message "Note" "设置orchestrator配置文件..."
cat > /etc/orchestrator.conf.json <<EOF
{
  "Debug": true,
  "EnableSyslog": false,
  "ListenAddress": ":${ORCH_PORT}",
  "MySQLTopologyUser": "${MySQLTopologyUser}",
  "MySQLTopologyPassword": "${MySQLTopologyPassword}",
  "MySQLTopologyCredentialsConfigFile": "",
  "MySQLTopologySSLPrivateKeyFile": "",
  "MySQLTopologySSLCertFile": "",
  "MySQLTopologySSLCAFile": "",
  "MySQLTopologySSLSkipVerify": true,
  "MySQLTopologyUseMutualTLS": false,
  "BackendDB": "sqlite",
  "SQLite3DataFile": "/usr/local/orchestrator/orchestrator.sqlite3",
  "MySQLConnectTimeoutSeconds": 1,
  "DefaultInstancePort": ${DefaultInstancePort},
  "DiscoverByShowSlaveHosts": true,
  "InstancePollSeconds": 5,
  "DiscoveryIgnoreReplicaHostnameFilters": [
    "a_host_i_want_to_ignore[.]example[.]com",
    ".*[.]ignore_all_hosts_from_this_domain[.]example[.]com",
    "a_host_with_extra_port_i_want_to_ignore[.]example[.]com:3307"
  ],
  "UnseenInstanceForgetHours": 240,
  "SnapshotTopologiesIntervalHours": 0,
  "InstanceBulkOperationsWaitTimeoutSeconds": 10,
  "HostnameResolveMethod": "default",
  "MySQLHostnameResolveMethod": "@@hostname",
  "SkipBinlogServerUnresolveCheck": true,
  "ExpiryHostnameResolvesMinutes": 60,
  "RejectHostnameResolvePattern": "",
  "ReasonableReplicationLagSeconds": 10,
  "ProblemIgnoreHostnameFilters": [],
  "VerifyReplicationFilters": false,
  "ReasonableMaintenanceReplicationLagSeconds": 20,
  "CandidateInstanceExpireMinutes": 60,
  "AuditLogFile": "",
  "AuditToSyslog": false,
  "RemoveTextFromHostnameDisplay": ".mydomain.com:3306",
  "ReadOnly": false,
  "AuthenticationMethod": "basic",
  "HTTPAuthUser": "${HTTPAuthUser}",
  "HTTPAuthPassword": "${HTTPAuthPassword}",
  "AuthUserHeader": "",
  "PowerAuthUsers": [
    "*"
  ],
  "ClusterNameToAlias": {
    "127.0.0.1": "test suite"
  },
  "ReplicationLagQuery": "",
  "DetectClusterAliasQuery": "SELECT SUBSTRING_INDEX(@@hostname, '.', 1)",
  "DetectClusterDomainQuery": "",
  "DetectInstanceAliasQuery": "",
  "DetectPromotionRuleQuery": "",
  "DataCenterPattern": "[.]([^.]+)[.][^.]+[.]mydomain[.]com",
  "PhysicalEnvironmentPattern": "[.]([^.]+[.][^.]+)[.]mydomain[.]com",
  "PromotionIgnoreHostnameFilters": [],
  "DetectSemiSyncEnforcedQuery": "",
  "ServeAgentsHttp": false,
  "AgentsServerPort": ":13001",
  "AgentsUseSSL": false,
  "AgentsUseMutualTLS": false,
  "AgentSSLSkipVerify": false,
  "AgentSSLPrivateKeyFile": "",
  "AgentSSLCertFile": "",
  "AgentSSLCAFile": "",
  "AgentSSLValidOUs": [],
  "UseSSL": false,
  "UseMutualTLS": false,
  "SSLSkipVerify": false,
  "SSLPrivateKeyFile": "",
  "SSLCertFile": "",
  "SSLCAFile": "",
  "SSLValidOUs": [],
  "URLPrefix": "",
  "StatusEndpoint": "/api/status",
  "StatusSimpleHealth": true,
  "StatusOUVerify": false,
  "AgentPollMinutes": 60,
  "UnseenAgentForgetHours": 6,
  "StaleSeedFailMinutes": 60,
  "SeedAcceptableBytesDiff": 8192,
  "PseudoGTIDPattern": "",
  "PseudoGTIDPatternIsFixedSubstring": false,
  "PseudoGTIDMonotonicHint": "asc:",
  "DetectPseudoGTIDQuery": "",
  "BinlogEventsChunkSize": 10000,
  "SkipBinlogEventsContaining": [],
  "ReduceReplicationAnalysisCount": true,
  "FailureDetectionPeriodBlockMinutes": 5,
  "FailMasterPromotionOnLagMinutes": 0,
  "RecoveryPeriodBlockSeconds": 300,
  "RecoveryIgnoreHostnameFilters": [],
  "RecoverMasterClusterFilters": [
    "*"
  ],
  "RecoverIntermediateMasterClusterFilters": [
    "*"
  ],
  "OnFailureDetectionProcesses": [
    "echo 'Detected {failureType} on {failureCluster}. Affected replicas: {countSlaves}' >> /tmp/recovery.log"
  ],
  "PreGracefulTakeoverProcesses": [
    "echo 'Planned takeover about to take place on {failureCluster}. Master will switch to read_only' >> /tmp/recovery.log",
    "/usr/local/orchestrator/orch_set_mysql_variables_pregraceful.sh {failedHost} >> /tmp/orch_set.log"
  ],
  "PreFailoverProcesses": [
    "echo 'Will recover from {failureType} on {failureCluster}' >> /tmp/recovery.log"
  ],
  "PostFailoverProcesses": [
    "echo '(for all types) Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Successor: {successorHost}:{successorPort}' >> /tmp/recovery.log",
    "/usr/local/orchestrator/orch_hook.sh {failureType} {failureClusterAlias} {failedHost} {successorHost} >> /tmp/orch.log",
    "/usr/local/orchestrator/orch_set_mysql_variables.sh {successorHost} >> /tmp/orch_set.log",
    "/usr/local/orchestrator/warning_dingding.sh {failedHost} {successorHost} >> /tmp/orch.log"
  ],
  "PostUnsuccessfulFailoverProcesses": [],
  "PostMasterFailoverProcesses": [
    "echo 'Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Promoted: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostIntermediateMasterFailoverProcesses": [
    "echo 'Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Successor: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostGracefulTakeoverProcesses": [
    "echo 'Planned takeover complete' >> /tmp/recovery.log",
    "/usr/local/orchestrator/orch_set_mysql_variables_postgraceful.sh {failedHost} >> /tmp/orch_set.log"
  ],
  "CoMasterRecoveryMustPromoteOtherCoMaster": true,
  "DetachLostSlavesAfterMasterFailover": true,
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "PreventCrossDataCenterMasterFailover": false,
  "PreventCrossRegionMasterFailover": false,
  "MasterFailoverDetachReplicaMasterHost": false,
  "MasterFailoverLostInstancesDowntimeMinutes": 0,
  "PostponeReplicaRecoveryOnLagMinutes": 0,
  "OSCIgnoreHostnameFilters": [],
  "GraphiteAddr": "",
  "GraphitePath": "",
  "GraphiteConvertHostnameDotsToUnderscores": true,
  "ConsulAddress": "",
  "ConsulAclToken": ""
}
EOF
}


### orch_hook.sh
add_orch_hook(){
print_message "Note" "设置切换脚本orch_hook.sh"
cat >/usr/local/orchestrator/orch_hook.sh <<EOF
#!/bin/bash

isitdead=\$1
cluster=\$2
oldmaster=\$3
newmaster=\$4
mysqluser="orchestrator"
export MYSQL_PWD="xxxpassxxx"

logfile="/var/log/orch_hook.log"

# list of clusternames
#clusternames=(rep blea lajos)

# clustername=( interface IP user Inter_IP)
#rep=( ens32 "192.168.56.121" root "192.168.56.125")

if [[ \$isitdead == "DeadMaster" ]]; then

    array=( ens32 "192.168.2.111" root "192.168.2.151")
    interface=\${array[0]}
    IP=\${array[1]}
    user=\${array[2]}

    if [ ! -z \${IP} ] ; then

        echo \$(date)
        echo "Revocering from: \$isitdead"
        echo "New master is: \$newmaster"
        echo "/usr/local/orchestrator/orch_vip.sh -d 1 -n \$newmaster -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s \"-p ${SSH_PORT}\"" | tee \$logfile
        /usr/local/orchestrator/orch_vip.sh -d 1 -n \$newmaster -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s "-p ${SSH_PORT}"
        #mysql -h\$newmaster -u\$mysqluser < /usr/local/bin/orch_event.sql
    else

        echo "Cluster does not exist!" | tee \$logfile

    fi
elif [[ \$isitdead == "DeadIntermediateMasterWithSingleSlaveFailingToConnect" ]]; then

    array=( ens32 "192.168.2.111" root "192.168.2.151")
    interface=\${array[0]}
    IP=\${array[3]}
    user=\${array[2]}
    slavehost=\`echo \$5 | cut -d":" -f1\`

    echo \$(date)
    echo "Revocering from: \$isitdead"
    echo "New intermediate master is: \$slavehost"
    echo "/usr/local/orchestrator/orch_vip.sh -d 1 -n \$slavehost -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s \"-p ${SSH_PORT}\"" | tee \$logfile
    /usr/local/orchestrator/orch_vip.sh -d 1 -n \$slavehost -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s "-p ${SSH_PORT}"


elif [[ \$isitdead == "DeadIntermediateMaster" ]]; then

        array=( ens32 "192.168.2.111" root "192.168.2.151")
        interface=\${array[0]}
        IP=\${array[3]}
        user=\${array[2]}
    slavehost=\`echo \$5 | sed -E "s/:[0-9]+//g" | sed -E "s/,/ /g"\`
    showslave=\`mysql -h\$newmaster -u\$mysqluser -sN -e "SHOW SLAVE HOSTS;" | awk '{print \$2}'\`
    newintermediatemaster=\`echo \$slavehost \$showslave | tr ' ' '\n' | sort | uniq -d\`

    echo \$(date)
    echo "Revocering from: \$isitdead"
    echo "New intermediate master is: \$newintermediatemaster"
    echo "/usr/local/orchestrator/orch_vip.sh -d 1 -n \$newintermediatemaster -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s \"-p ${SSH_PORT}\"" | tee \$logfile
    /usr/local/orchestrator/orch_vip.sh -d 1 -n \$newintermediatemaster -i \${interface} -I \${IP} -u \${user} -o \$oldmaster -s "-p ${SSH_PORT}"

fi
EOF

chmod +x /usr/local/orchestrator/orch_hook.sh

sed -i "s/array=.*/array=( ${NetworkCardName} '${Vip}' root '${CurrentIP}')/g" /usr/local/orchestrator/orch_hook.sh
}

#### orch_vip.sh
add_orch_vip(){
print_message "Note" "设置切换脚本orch_vip.sh"
cat >/usr/local/orchestrator/orch_vip.sh <<"EOF2"
#!/bin/bash

emailaddress="email@example.com"
sendmail=0

function usage {
  cat << EOF
 usage: $0 [-h] [-d master is dead] [-o old master ] [-s ssh options] [-n new master] [-i interface] [-I] [-u SSH user]
 
 OPTIONS:
    -h        Show this message
    -o string Old master hostname or IP address 
    -d int    If master is dead should be 1 otherweise it is 0
    -s string SSH options
    -n string New master hostname or IP address
    -i string Interface exmple eth0:1
    -I string Virtual IP
    -u string SSH user
EOF

}

while getopts ho:d:s:n:i:I:u: flag; do
  case $flag in
    o)
      orig_master="$OPTARG";
      ;;
    d)
      isitdead="${OPTARG}";
      ;;
    s)
      ssh_options="${OPTARG}";
      ;;
    n)
      new_master="$OPTARG";
      ;;
    i)
      interface="$OPTARG";
      ;;
    I)
      vip="$OPTARG";
      ;;
    u)
      ssh_user="$OPTARG";
      ;;
    h)
      usage;
      exit 0;
      ;;
    *)
      usage;
      exit 1;
      ;;
  esac
done


if [ $OPTIND -eq 1 ]; then 
    echo "No options were passed"; 
    usage;
fi

shift $(( OPTIND - 1 ));

# discover commands from our path
ssh=$(which ssh)
arping=$(which arping)
ip2util=$(which ip)

# command for adding our vip
cmd_vip_add="sudo -n $ip2util address add ${vip} dev ${interface}"
# command for deleting our vip
cmd_vip_del="sudo -n $ip2util address del ${vip}/32 dev ${interface}"
# command for discovering if our vip is enabled
cmd_vip_chk="sudo -n $ip2util address show dev ${interface} to ${vip%/*}/32"
# command for sending gratuitous arp to announce ip move
cmd_arp_fix="sudo -n $arping -c 1 -I ${interface} ${vip%/*}   "
# command for sending gratuitous arp to announce ip move on current server
cmd_local_arp_fix="sudo -n $arping -c 1 -I ${interface} ${vip%/*}   "

vip_stop() {
    rc=0

    # ensure the vip is removed
    $ssh ${ssh_options} -tt ${ssh_user}@${orig_master} \
    "[ -n \"\$(${cmd_vip_chk})\" ] && ${cmd_vip_del} && sudo ${ip2util} route flush cache || [ -z \"\$(${cmd_vip_chk})\" ]"
    rc=$?
    return $rc
}

vip_start() {
    rc=0

    # ensure the vip is added
    # this command should exit with failure if we are unable to add the vip
    # if the vip already exists always exit 0 (whether or not we added it)
    $ssh ${ssh_options} -tt ${ssh_user}@${new_master} \
     "[ -z \"\$(${cmd_vip_chk})\" ] && ${cmd_vip_add} && ${cmd_arp_fix} || [ -n \"\$(${cmd_vip_chk})\" ]"
    rc=$?
    $cmd_local_arp_fix
    return $rc
}

vip_status() {
    $arping -c 1 -I ${interface} ${vip%/*}   
    if ping -c 1 -W 1 "$vip"; then
        return 0
    else
        return 1
    fi
}

if [[ $isitdead == 0 ]]; then
    echo "Online failover"
    if vip_stop; then 
        if vip_start; then
            echo "$vip is moved to $new_master."
            if [ $sendmail -eq 1 ]; then mail -s "$vip is moved to $new_master." "$emailaddress" < /dev/null &> /dev/null  ; fi
        else
            echo "Can't add $vip on $new_master!" 
            if [ $sendmail -eq 1 ]; then mail -s "Can't add $vip on $new_master!" "$emailaddress" < /dev/null &> /dev/null  ; fi
            exit 1
        fi
    else
        echo $rc
        echo "Can't remove the $vip from orig_master!"
        if [ $sendmail -eq 1 ]; then mail -s "Can't remove the $vip from orig_master!" "$emailaddress" < /dev/null &> /dev/null  ; fi
        exit 1
    fi


elif [[ $isitdead == 1 ]]; then
    echo "Master is dead, failover"
    # make sure the vip is not available 
    if vip_status; then 
        if vip_stop; then
            if [ $sendmail -eq 1 ]; then mail -s "$vip is removed from orig_master." "$emailaddress" < /dev/null &> /dev/null  ; fi
        else
            if [ $sendmail -eq 1 ]; then mail -s "Couldn't remove $vip from orig_master." "$emailaddress" < /dev/null &> /dev/null  ; fi
            exit 1
        fi
    fi

    if vip_start; then
          echo "$vip is moved to $new_master."
          if [ $sendmail -eq 1 ]; then mail -s "$vip is moved to $new_master." "$emailaddress" < /dev/null &> /dev/null  ; fi

    else
          echo "Can't add $vip on $new_master!" 
          if [ $sendmail -eq 1 ]; then mail -s "Can't add $vip on $new_master!" "$emailaddress" < /dev/null &> /dev/null  ; fi
          exit 1
    fi
else
    echo "Wrong argument, the master is dead or live?"

fi
EOF2

chmod +x /usr/local/orchestrator/orch_vip.sh
}

ding_test(){
  ${SCRIPT_DIR}/send_ding_msg.sh "钉钉连通性测试" "测试" "测试钉钉是否可正常发送!\n\n 发送服务器:${IPADDR}"
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
cp /tmp/warning_dingding.sh /usr/local/orchestrator/ 
cp ${SCRIPT_DIR}/dingtalk_send /usr/local/orchestrator/
}

add_orch_set_mysql_variables(){
print_message "Note" "设置切换后MySQl脚本orch_set_mysql_variables.sh"
if [[ $MYSQL_VERSION > "8.0.25" ]];then
  SQL_CMD="set global super_read_only = 0;set global read_only = 0;set global rpl_semi_sync_source_enabled = 1;set global rpl_semi_sync_replica_enabled = 0;"
else
  SQL_CMD="set global super_read_only = 0;set global read_only = 0;set global rpl_semi_sync_master_enabled = 1;set global rpl_semi_sync_slave_enabled = 0;"
fi
cat >/usr/local/orchestrator/orch_set_mysql_variables.sh <<EOF
#!/bin/bash
newmaster=\$1
echo "当前的新主为:  \$newmaster, 将read_only 设置为0，将rpl_semi_sync_source_enabled设置为1，rpl_semi_sync_reolica_enabled设置为0。"
/usr/local/mysql/bin/mysql -h\$newmaster -u${MySQLTopologyUser} -p'${MySQLTopologyPassword}' -P${DefaultInstancePort} -e '${SQL_CMD}'
EOF
chmod +x /usr/local/orchestrator/orch_set_mysql_variables.sh
}

orch_set_mysql_variables_pregraceful(){
  print_message "Note" "设置优雅切换前执行的MySQl脚本orch_set_mysql_variables_pregraceful.sh"
if [[ $MYSQL_VERSION > "8.0.25" ]];then
  SQL_CMD="set global super_read_only = 1;set global read_only = 1;"
else
  SQL_CMD="set global super_read_only = 1;set global read_only = 1;"
fi
cat > /usr/local/orchestrator/orch_set_mysql_variables_pregraceful.sh <<EOF
#!/bin/bash
oldmaster=\$1
echo "\`date +%Y-%m-%dT%H:%M:%S\` 切换前设置旧主 \$1 为read_only=1,super_read_only=1..."
/usr/local/mysql/bin/mysqladmin -h\$oldmaster -u${MySQLTopologyUser} -p'${MySQLTopologyPassword}' -P${DefaultInstancePort} ping &>/dev/null
if [ \$? -eq 0 ]
then
  echo "\`date +%Y-%m-%dT%H:%M:%S\` 修改旧主为只读：${SQL_CMD}"
  /usr/local/mysql/bin/mysql -h\$oldmaster -u${MySQLTopologyUser} -p'${MySQLTopologyPassword}' -P${DefaultInstancePort} -e '${SQL_CMD}'
else
  echo "\`date +%Y-%m-%dT%H:%M:%S\` Old Mysql is down"
fi
EOF
chmod +x /usr/local/orchestrator/orch_set_mysql_variables_pregraceful.sh
}

orch_set_mysql_variables_postgraceful(){
  print_message "Note" "设置优雅切换后执行的MySQl脚本orch_set_mysql_variables_postgraceful.sh"
if [[ $MYSQL_VERSION > "8.0.25" ]];then
  SQL_CMD="set global rpl_semi_sync_source_enabled = 0;set global rpl_semi_sync_replica_enabled = 1;set global super_read_only = 1;set global read_only = 1;start replica;"
else
  SQL_CMD="set global rpl_semi_sync_master_enabled = 0;set global rpl_semi_sync_slave_enabled = 1;set global super_read_only = 1;set global read_only = 1;start slave;"
fi
cat > /usr/local/orchestrator/orch_set_mysql_variables_postgraceful.sh <<EOF
#!/bin/bash
oldmaster=\$1
echo "\`date +%Y-%m-%dT%H:%M:%S\` 切换后设置旧主 \$1 为read_only=1,super_read_only=1,且启动复制..."
/usr/local/mysql/bin/mysqladmin -h\$oldmaster -u${MySQLTopologyUser} -p'${MySQLTopologyPassword}' -P${DefaultInstancePort} ping &>/dev/null
if [ \$? -eq 0 ]
then
  echo "\`date +%Y-%m-%dT%H:%M:%S\` 修改旧主参数为从库所需要设置的参数：${SQL_CMD}"
  /usr/local/mysql/bin/mysql -h\$oldmaster -u${MySQLTopologyUser} -p'${MySQLTopologyPassword}' -P${DefaultInstancePort} -e '${SQL_CMD}'
else
  echo "\`date +%Y-%m-%dT%H:%M:%S\` Old Mysql is down"
fi
EOF
chmod +x /usr/local/orchestrator/orch_set_mysql_variables_postgraceful.sh
}

# 配置orch高可用
add_orch_raft(){
  print_message "Note" "配置orchestrator组件raft功能"
  if [ $RaftNodes ];then
    print_message "Note" "进行组件Raft配置"
    sed -i 's/^  "ConsulAclToken": ""*/  "ConsulAclToken": "",\n\n  "RaftEnabled": true\,\n  "RaftDataDir": "\/usr\/local\/orchestrator",\n  "RaftBind": "'${RaftBind}'"\,\n  "DefaultRaftPort": 10008\,\n  "RaftNodes":[\n    "'${ArrNodes[0]}'"\,\n    "'${ArrNodes[1]}'"\,\n    "'${ArrNodes[2]}'"\n  ]\n/' /etc/orchestrator.conf.json
    print_message "Note" "组件Raft配置完成[当前配置服务器$RaftNodes，配置信息 ${ArrNodes[*]}]"
  fi
}

systemctl_reload(){
  print_message "Note" "执行 systemctl daemon-reload..."
  systemctl daemon-reload
}

start_orch(){
 print_message "Note" "启动orchestrator"
 systemctl start orchestrator
 systemctl status orchestrator
}

env_orch(){
  echo "export ORCHESTRATOR_API=\"${ArrNodes[0]}:${ORCH_PORT}/api ${ArrNodes[1]}:${ORCH_PORT}/api ${ArrNodes[2]}:${ORCH_PORT}/api\"" > /etc/profile.d/orchestrator_set_env.sh
  print_message "Note" "\033[33m 请立即手动执行\n source /etc/profile.d/mysql_set_env.sh \n source /etc/profile.d/orchestrator_set_env.sh \033[0m"
  print_message "Note" "\033[33m 请在整个集群安装完成后,使用浏览器登陆已安装组件中的任意一地址，如：\n ${ArrNodes[0]}:${ORCH_PORT}，Clusters --> Discover   填入任一集群MySQL地址与端口\n或任意一服务器执行 orchestrator-client -b 配置的用户名:密码 -c discover -i MySQL的IP:端口。用于进行拓扑发现 \033[0m"
}


check_params
install_orchestrator
add_orch_conf
add_orch_hook
add_orch_vip
add_orch_raft
add_orch_set_mysql_variables
orch_set_mysql_variables_pregraceful
orch_set_mysql_variables_postgraceful
systemctl_reload
start_orch
set_warning_script
env_orch

