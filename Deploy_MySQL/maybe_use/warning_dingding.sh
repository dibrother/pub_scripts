#!/bin/bash

OLD_MASTER=$1
NEW_MASTER=$2
LOCAL_HOST_IP='192.168.66.166'
#msg_title="钉钉消息通知"
HAPPEN_TIME=`date "+%Y-%m-%d %H:%M:%S"`

DINGDING_SWITCH=1
MSG_TITLE="数据库切换告警"
WEBHOOK_URL='https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxx'
SECRET='SECxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
# 支持 text/markdown
SEND_TYPE="markdown"
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=""
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=""

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
      DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}"`
    fi
    if [ "${DING_STATUS}" = '{"errcode":0,"errmsg":"ok"}' ];then
      print_message "Note" "钉钉消息发送成功"
    else
      print_message "Error" "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\""
      exit 1
    fi
    print_message "通知" "钉钉通知完成..."
  fi
}

check_switch_status(){
  if [ -f /tmp/orch.log ];then
    SWITCH_STATUS=`tail -3 /tmp/orch.log |grep 'is moved to'|wc -l`
    if [ ${SWITCH_STATUS} -eq 1 ];then
      SWITCH_STATUS_MSG='VIP切换成功'
    else
      SWITCH_STATUS_MSG='VIP切换失败,请检查!'
    fi
  else
    SWITCH_STATUS_MSG='不存在日志/tmp/orch.log,请检查!'
  fi
  if [ -f /tmp/recovery.log ];then
    SWITCH_MSG=`tail -1 /tmp/recovery.log`
  else
    SWITCH_MSG="不存在日志 /tmp/recovery.log,请检查!"
  fi
}

dingding_send(){
  if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    local DING_MSG="\n #### **<font color=#FF0033>发生高可用切换</font>** \n* 原主IP：${OLD_MASTER}\n* 新主IP：${NEW_MASTER}\n* vip切换状态:${SWITCH_STATUS_MSG} \n* 执行切换操作服务器IP: ${LOCAL_HOST_IP}\n* 切换信息:${SWITCH_MSG} \n*---\n 发生时间:\n ${HAPPEN_TIME}"
    dingding_note "异常" "${DING_MSG}"
  else
    print_message "通知" "发生切换,但未配置钉钉告警."
  fi
}
  
check_switch_status
dingding_send
