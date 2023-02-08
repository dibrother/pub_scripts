#!/bin/bash
set -e

#加载配置文件,读取到钉钉相关的信息
SCRIPT_DIR=$(cd `dirname $0`; pwd)
source ${SCRIPT_DIR}/config/user.conf
# 传入参数
SEND_TITLE=$1
SEND_NOTE=$2
SEND_MSG=$3
SEND_TYPE=${4:-"markdown"}

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
  #if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    print_message "Note" "发送钉钉通知..."
    if [[ ${SEND_NOTE} == "通知" ]]; then
      local color="#006600"
    else
      local color="#FF0033"
    fi
    local DING_MESSAGE="**[<font color=${color}>${SEND_NOTE}</font>]** \n \n--- \n${SEND_MSG}"
    if [[ ${IS_AT_ALL} ]];then
      DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${SEND_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_all`
    elif [[ ${AT_MOBILES} ]];then
     DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${SEND_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_mobiles ${AT_MOBILES}`
    else
      #echo "${SCRIPT_DIR}/dingtalk_send -url \"${WEBHOOK_URL}\" -secert \"${SECRET}\" -title \"${SEND_TITLE}\" -type \"${SEND_TYPE}\" -msg \"${DING_MESSAGE}\""
      DING_STATUS=`${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${SEND_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}"`
    fi
    if [ "${DING_STATUS}" = '{"errcode":0,"errmsg":"ok"}' ];then
      print_message "Note" "钉钉消息发送成功"
    else
      print_message "Error" "钉钉消息发送失败,请检查!\n 执行钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\"\n错误信息为:${DING_STATUS}"
      exit 1
    fi
  #fi
}
if [ ${SEND_TITLE} ] && [ ${SEND_MSG} ] && [ ${SEND_NOTE} ];then
  dingding_note "${SEND_TITLE}" "${SEND_TYPE}" "${SEND_MSG}"
else
  printf "Usage: 
       send_ding_msg.sh {title} {通知/异常/其他信息} {message}\n"
fi
