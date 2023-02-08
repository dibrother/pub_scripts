#!/bin/bash
set -e

# 脚本存放位置,需要与钉钉告警脚本dingtalk_send同目录下
SCRIPT_DIR=$(cd `dirname $0`; pwd)
########################## MySQL 本地备份相关设置/远程的话为接收端用户 ##############################
MYSQL_BIN_DIR=/usr/local/mysql/bin/mysql
MYSQL_CNF_DIR=/data/mysql3312/my3312.cnf
CLONE_USER='clone_user'
CLONE_PWD='123456'
PORT=3312
HOST_IP=192.168.66.169

######################### 备份相关设置 ##################################
# 备份存储路径记得需要MySQL有创建权限，需要 chown -R mysql:mysql 
BACK_DIR='/data/clonebak'
BACKUP_PREFIX_NAME="clone_full"
SAVE_DAYS=7
# 备份是否压缩
COMPRESS_SWITCH=1
########################  获取备份机磁盘信息，获取脚本执行的当前服务器磁盘信息  ###############################
LOCAL_DISK_CMD=`df -Th|grep centos-root|awk '{print $6}'`

######################### 远程发送端MySQL相关设置 ##################################
DONOR_CLONE_USER='clone_user'
DONOR_CLONE_PWD='123456'
DONOR_PORT=3312
DONOR_HOST_IP=192.168.1.27

########################  dingding通知配置  ##########################
DINGDING_SWITCH=1
MSG_TITLE="数据库备份"
WEBHOOK_URL='https://oapi.dingtalk.com/robot/send?access_token=97d0d56cb96b28d141f847f157d578177ff3b1aac2d50ce30b5505dcdd16b2f7'
SECRET='SECc489e9a2084489856788df7c09ad325e550db42fbc27c141f80a68ffd7266ed4'
# 支持 text/markdown
SEND_TYPE="markdown"
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=""
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=""


######################## 不需要改动 ##############################################
BACKUP_DATETIME=`date +%Y%m%d%H%M%S`
BACK_NAME=${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}

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

backup_environment_check(){
  print_message "Note" "进行备份前预检查"
  if [ ! -e ${CLONE_USER} ] || [ ! -e ${MYSQL_CNF_DIR} ] || [ ! ${CLONE_USER} ] || [ ! ${CLONE_PWD} ] || [ ! ${PORT} ] || [ ! ${HOST_IP} ];then
    print_message "Error" "MySQL相关参数设置缺漏，请确认！"
    exit 1
  fi

  if [ ! -d ${BACK_DIR} ] || [ ! ${BACKUP_PREFIX_NAME} ] || [ ! ${SAVE_DAYS} ];then
    print_message "Error" "备份相关参数设置缺漏，请确认！"
    exit 1
  fi
}

remote_backup_environment_check(){
  if [ ! -e ${DONOR_MYSQL_BIN_DIR} ] || [ ! ${DONOR_CLONE_USER} ] || [ ! ${DONOR_CLONE_PWD} ] || [ ! ${DONOR_PORT} ] || [ ! ${DONOR_HOST_IP} ] || [ ! -d ${BACK_DIR} ];then
    print_message "Error" "接收端相关参数设置缺漏，请确认！"
    exit 1
  fi  
}

dingding_test(){
  local DING_MSG="钉钉连通性测试"
  local DING_STATUS=`dingding_note "通知" "${DING_MSG}"`
  if [ ${DING_STATUS} != '{"errcode":0,"errmsg":"ok"}' ];then
    echo "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\""
  fi
}

clone_backup_local(){
  print_message "Note" "开始本地clone备份..."
  local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e "CLONE LOCAL DATA DIRECTORY = '${BACK_DIR}/${BACK_NAME}';"
  backup_compress
  local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"`

  BACK_STATUS=`${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -NBe"select count(*) from performance_schema.clone_progress where STATE not in ('Completed','Not Started');"`
  if [ $BACK_STATUS -eq 0 ];then
    print_message "Note" "[${BACK_NAME}]clone备份成功"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local BACKUP_FILE_SIZE=`du -sh ${BACK_DIR}/${BACK_NAME}*|awk '{print $1}'`
      local DING_MSG="\n* 备份文件:${BACK_NAME}\n* 文件大小：${BACKUP_FILE_SIZE}\n* 备份目录：${BACK_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      dingding_note "通知" "${DING_MSG}"
    fi
  else
    print_message "Error" "[${BACK_NAME}]clone备份失败"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local DING_MSG="**<font color=#FF0033>备份失败,请检查!!!</font>**\n* 备份文件:${BACK_NAME}\n* 备份目录：${BACK_DIR}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      dingding_note "异常" "${DING_MSG}"
    fi
    exit 1
  fi
}

clone_backup_remote(){
  print_message "Note" "开始远程clone备份..."
  local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e " SET GLOBAL clone_valid_donor_list = '${DONOR_HOST_IP}:${DONOR_PORT}';"
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e "CLONE INSTANCE FROM '${DONOR_CLONE_USER}'@'${DONOR_HOST_IP}':${DONOR_PORT} IDENTIFIED BY '${DONOR_CLONE_PWD}' DATA DIRECTORY = '${BACK_DIR}/${BACK_NAME}';"
  
  backup_compress
  local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"`

  BACK_STATUS=`${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -NBe"select count(*) from performance_schema.clone_progress where STATE not in ('Completed','Not Started');"`
  if [ $BACK_STATUS -eq 0 ];then
    print_message "Note" "[${BACK_NAME}]远程clone备份成功"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local BACKUP_FILE_SIZE=`du -sh ${BACK_DIR}/${BACK_NAME}*|awk '{print $1}'`
      local DING_MSG="\n* 备份文件:${BACK_NAME}\n* 文件大小：${BACKUP_FILE_SIZE}\n* 备份目录：${BACK_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE}\n* 被备份源主机：${HOST_IP}\n* 执行备份主机：${DONOR_HOST_IP}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      dingding_note "通知" "${DING_MSG}"
    fi
  else
    print_message "Error" "[${BACK_NAME}]远程clone备份失败"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local DING_MSG="**<font color=#FF0033>备份失败,请检查!!!</font>**\n* 备份文件:${BACK_NAME}\n* 备份目录：${BACK_DIR}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      dingding_note "异常" "${DING_MSG}"
    fi
    exit 1
  fi
}

# 钉钉信息发送
## $1 通知/异常
## $2 发送信息
dingding_note(){
  if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    #echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 发送钉钉通知..."
    print_message "Note" "发送钉钉通知..."
    if [[ $1 == "通知" ]]; then
      local color="#006600"
    else
      local color="#FF0033"
    fi
    local DING_MESSAGE="**[<font color=${color}>$1</font>]** \n --- \n$2"
    if [[ ${IS_AT_ALL} ]];then
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_all
    elif [[ ${AT_MOBILES} ]];then
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_mobiles ${AT_MOBILES}
    else
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}"
    fi
    #echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 钉钉通知完成..."
    print_message "Note" "钉钉通知发送完成..."
  fi
}

his_backup_clean(){
  if [ -d ${BACK_DIR} ];then
    print_message "Note" "开始清理备份..."
    if [[ ${COMPRESS_SWITCH} -eq 1 ]];then
      REMOVE_BACKUPS=`find ${BACK_DIR} -type f -name "${BACKUP_PREFIX_NAME}_*.tar.gz" -mtime +${SAVE_DAYS}`
      find ${BACK_DIR} -type f -name "${BACKUP_PREFIX_NAME}_*.tar.gz" -mtime +${SAVE_DAYS} | xargs rm -f
    else
      REMOVE_BACKUPS=`find ${BACK_DIR} -type d -name "${BACKUP_PREFIX_NAME}_" -mtime +${SAVE_DAYS}`
      find ${BACK_DIR} -type d -name "${BACKUP_PREFIX_NAME}_*" -mtime +${SAVE_DAYS} | xargs rm -rf
    fi 
    print_message "Note" "清理完成,清理的是：${REMOVE_BACKUPS}"
  fi
}

backup_compress(){
  if [[ ${COMPRESS_SWITCH} -eq 1 ]];then
    print_message "Note" "进行备份压缩..."
    cd ${BACK_DIR}
    tar zcf ${BACK_DIR}/${BACK_NAME}.tar.gz ${BACK_NAME}
    if [[ -d ${BACK_DIR}/${BACK_NAME} ]] && [[ -f ${BACK_DIR}/${BACK_NAME}.tar.gz ]];then
      print_message "Note" "删除已压缩文件"
      rm -rf ${BACK_DIR}/${BACK_NAME}
    fi
    print_message "Note" "文件压缩完成"
  fi
}

if [ "$1" = "local" ];then
  backup_environment_check
  dingding_test
  clone_backup_local
  his_backup_clean
elif [ "$1" = "remote" ];then
  remote_backup_environment_check
  dingding_test
  clone_backup_remote
  his_backup_clean
else
  printf "Usage:
      bash clone_backup.sh local    本地备份
      bash clone_backup.sh remote   远程备份\n"
  exit 1
fi
