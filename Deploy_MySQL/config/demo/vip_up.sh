#!/bin/bash

# 当前脚本适用于中间件为 replication-manager 的高可用VIP切换,
# 接收传入参数 cluster.oldMaster.Host cluster.master.Host cluster.oldMaster.Port cluster.master.Port
orig_master=$1
new_master=$2
old_port=$3
new_port=$4

mysql_user='ha_monitor'
mysql_password='WWUlyFK6X!VkR4dQ'

emailaddress="email@example.com"
sendmail=0

# 根据环境配置
# 网卡名称
interface=ens33
# VIP
vip=192.168.60.111
# ssh用户
ssh_options='-p6122'
ssh_user='root'


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
cmd_arp_fix="sudo -n $arping -c 1 -I ${interface} ${vip%/*}"
# command for sending gratuitous arp to announce ip move on current server
cmd_local_arp_fix="sudo -n $arping -c 1 ${vip%/*}"

SCRIPT_DIR=$(cd `dirname $0`; pwd)
########################  dingding通知配置[可选修改]  ##########################
DINGDING_SWITCH=0
MSG_TITLE='数据库切换告警'
WEBHOOK_URL='https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
SECRET='SECxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
# 支持 text/markdown
SEND_TYPE='markdown'
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=''
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=''

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

# 钉钉信息发送
## $1 通知/异常
## $2 发送信息
dingding_note(){
  if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    print_message "通知" "发送钉钉通知..."
    if [[ $1 == "通知" ]]; then
      local color="#006600"
    else
      local color="#FF0033"
    fi
    local DING_MESSAGE="**[<font color=${color}>$1</font>]** \n \n--- \n$2"
    if [[ ${IS_AT_ALL} ]];then
      DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_all`
    elif [[ ${AT_MOBILES} ]];then
     DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_mobiles ${AT_MOBILES}`
    else
      #echo "${SCRIPT_DIR}/dingtalk_send -url \"${WEBHOOK_URL}\" -secert \"${SECRET}\" -title \"${MSG_TITLE}\" -type \"${SEND_TYPE}\" -msg \"${DING_MESSAGE}\""
      DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}"`
    fi
    if [ "${DING_STATUS}" = '{"errcode":0,"errmsg":"ok"}' ];then
      print_message "Note" "钉钉消息发送成功"
    else
      print_message "Error" "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\""
      #exit 1
    fi
    print_message "通知" "钉钉通知完成..."
  fi
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

change_master_params(){
  mysql_version=`/usr/local/mysql/bin/mysql -h${new_master} -u${mysql_user} -p${mysql_password} -P${new_port} -Ne "select version()"` 
  if [[ ${mysql_version} > "8.0.25" ]];then
    /usr/local/mysql/bin/mysql -h${new_master} -u${mysql_user} -p${mysql_password} -P${new_port} -e "set global read_only=0;set global super_read_only=0;set global rpl_semi_sync_source_enabled=1;set global rpl_semi_sync_replica_enabled=0;"
  else
    /usr/local/mysql/bin/mysql -h${new_master} -u${mysql_user} -p${mysql_password} -P${new_port} -e "set global read_only=0;set global super_read_only=0;set global rpl_semi_sync_master_enabled=1;set global rpl_semi_sync_slave_enabled=0;"
  fi
}


print_message "Note" "make vip up on new master..."
if vip_start; then
      print_message "Note" "$vip is moved to $new_master."
      change_master_params
      dingding_note "数据库切换" "$vip is moved to $new_master"
      #echo "`date +'%Y-%m-%d %T'` $vip is moved to $new_master."
      #if [ $sendmail -eq 1 ]; then mail -s "$vip is moved to $new_master." "$emailaddress" < /dev/null &> /dev/null  ; fi

else
      print_message "Note" "Can't add $vip on $new_master!"
      dingding_note "异常" "Can't add $vip on $new_master!!!"
      #echo "`date +'%Y-%m-%d %T'` Can't add $vip on $new_master!"
      #if [ $sendmail -eq 1 ]; then mail -s "Can't add $vip on $new_master!" "$emailaddress" < /dev/null &> /dev/null  ; fi
      exit 1
fi
