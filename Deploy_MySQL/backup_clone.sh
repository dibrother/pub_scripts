#!/bin/bash
#set -e

######################## 不需要改动 ##############################################
# 获取脚本绝对路径,需要与dingtaik_send在一个目录下
SCRIPT_DIR=$(cd `dirname $0`; pwd)
source ${SCRIPT_DIR}/config/backup_clone.conf
BACKUP_DATETIME=`date +%Y%m%d%H%M%S`
BACK_NAME=${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}
LOCAL_DISK_CMD=`df -Th ${BACK_DIR}|awk '{print $6}'|tail -1`

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

err_exit(){
  is_exec_success=$?
  if [ "A$is_exec_success" != "A0" ];then
    print_message "Error" "-------------------------- 备份失败,请检查!!! ----------------------- "
    local DING_MSG="**<font color=#FF0033>备份失败,请检查!!!</font>**\n* 备份文件:${BACK_NAME}\n* 备份目录：${BACK_DIR}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
    dingding_note "异常" "${DING_MSG}"
    exit 1
  fi
}

backup_environment_check(){
  print_message "Note" "进行备份前预检查"
  if [ ! ${MYSQL_BIN_DIR} ]  || [ ! ${MYSQL_CNF_DIR} ] || [ ! ${CLONE_USER} ] || [ ! ${CLONE_PWD} ] || [ ! ${PORT} ] || [ ! ${HOST_IP} ];then
    print_message "Error" "MySQL相关参数设置缺漏，请确认！"
    exit 1
  fi

  DISK_CMD_STATUS=${LOCAL_DISK_CMD}
  if [ ! ${BACK_DIR} ] || [ ! ${BACKUP_PREFIX_NAME} ] || [ ! ${SAVE_DAYS} ] || [ ! ${COMPRESS_SWITCH} ] || [ ! ${DISK_CMD_STATUS} ];then
    echo "BACK_DIR:${BACK_DIR}  BACKUP_PREFIX_NAME:${BACKUP_PREFIX_NAME} SAVE_DAYS:${SAVE_DAYS} COMPRESS_SWITCH:${COMPRESS_SWITCH} DISK_CMD_STATUS:${DISK_CMD_STATUS}"
    print_message "Error" "备份相关参数设置缺漏，请确认！"
    exit 1
  fi

  IP_IS_EXISTS=`ip -4 a|grep -w ${HOST_IP}|wc -l`
  if [ $IP_IS_EXISTS -eq 0 ];then
    print_message "Error" "设置的 HOST_IP 与当前服务器IP不匹配，请检查 config/backup_clone.conf 文件中的 HOST_IP 设置"
    exit 1
  fi
}

remote_backup_environment_check(){
  if [ ! ${DONOR_CLONE_USER} ] || [ ! ${DONOR_CLONE_PWD} ] || [ ! ${DONOR_PORT} ] || [ ! ${DONOR_HOST_IP} ] || [ ! -d ${BACK_DIR} ];then
    print_message "Error" "接收端相关参数设置缺漏，请确认！"
    exit 1
  fi
}

#dingding_test(){
#  local DING_MSG="钉钉连通性测试"
#  local DING_STATUS=`dingding_note "Note" "${DING_MSG}"`
#  if [ ${DING_STATUS} != '{"errcode":0,"errmsg":"ok"}' ];then
#    echo "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\""
#  fi
#}

clone_backup_local(){
  print_message "Note" "开始本地clone备份..."
  local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e "CLONE LOCAL DATA DIRECTORY = '${BACK_DIR}/${BACK_NAME}';"
  local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"`
  err_exit
  backup_cnf
  BACK_STATUS=`${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -NBe"select count(*) from performance_schema.clone_progress where STATE not in ('Completed','Not Started');"`
  if [ ${BACK_STATUS} ] && [ ${BACK_STATUS} -eq 0 ];then
    backup_compress
    print_message "Note" "[${BACK_NAME}]clone备份成功"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local BACKUP_FILE_SIZE=`du -sh ${BACK_DIR}/${BACK_NAME}*|awk '{print $1}'`
      local DING_MSG="\n* 备份文件:${BACK_NAME}\n* 文件大小：${BACKUP_FILE_SIZE}\n* 备份目录：${BACK_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE}\n* 执行备份主机:${HOST_IP}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
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
  print_message "Note" "开始远程clone备份,源地址：${DONOR_HOST_IP}:${DONOR_PORT}..."
  local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e " SET GLOBAL clone_valid_donor_list = '${DONOR_HOST_IP}:${DONOR_PORT}';"
  ${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -e "CLONE INSTANCE FROM '${DONOR_CLONE_USER}'@'${DONOR_HOST_IP}':${DONOR_PORT} IDENTIFIED BY '${DONOR_CLONE_PWD}' DATA DIRECTORY = '${BACK_DIR}/${BACK_NAME}';"
  err_exit
  backup_cnf
  local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"`

  BACK_STATUS=`${MYSQL_BIN_DIR} -u"${CLONE_USER}" -p"${CLONE_PWD}" -h${HOST_IP} -P${PORT} -NBe"select count(*) from performance_schema.clone_progress where STATE not in ('Completed','Not Started');"`
  if [ $BACK_STATUS -eq 0 ];then
    backup_compress
    print_message "Note" "[${BACK_NAME}]远程clone备份成功"
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local BACKUP_FILE_SIZE=`du -sh ${BACK_DIR}/${BACK_NAME}*|awk '{print $1}'`
      local DING_MSG="\n* 备份文件:${BACK_NAME}\n* 文件大小：${BACKUP_FILE_SIZE}\n* 备份目录：${BACK_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE} \n* 被备份源主机：${DONOR_HOST_IP}\n* 执行备份主机：${HOST_IP}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
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

# 备份 cnf 配置文件
backup_cnf(){
  print_message "Note" "备份my.cnf信息"
  if [ "${BACKUP_TYPE}" = "local" ];then
    cp ${MYSQL_CNF_DIR} ${BACK_DIR}/${BACK_NAME}/backup-my.cnf
  elif [ "${BACKUP_TYPE}" = "remote" ];then 
    BACK_VARIABLES=$(${MYSQL_BIN_DIR} -h${DONOR_HOST_IP} -u"${DONOR_CLONE_USER}" -p"${DONOR_CLONE_PWD}" -P${DONOR_PORT} -e"select concat(VARIABLE_NAME,' = ',VARIABLE_VALUE,'\n') from performance_schema.global_variables where VARIABLE_NAME in ('innodb_checksum_algorithm','innodb_log_checksums','innodb_data_file_path','innodb_log_files_in_group','innodb_log_file_size','innodb_page_size','innodb_undo_directory','innodb_undo_tablespaces','server_id','innodb_log_checksums','innodb_redo_log_encrypt','innodb_undo_log_encrypt','server_uuid','master_key_id');")
    echo -e ${BACK_VARIABLES} > ${BACK_DIR}/${BACK_NAME}/backup-my.cnf 
  fi
}

# 钉钉信息发送
## $1 通知/异常
## $2 发送信息
dingding_note(){
  if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    print_message "Note" "发送钉钉通知..."
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
    print_message "Note" "钉钉通知完成..."
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

# 添加定时任务
add_job_crontab()
{
  dingding_note "测试" "备份钉钉通知连通性测试\n\n 通知时间: `date +%F-%T`"

  cat >> /etc/crontab << EOF
# 每天凌晨2点55分执行备份
55 02 * * * root /bin/bash $1 > ${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_\`date '+\%Y\%m\%d\%H\%M\%S'\`_script.log 2>&1
EOF
}

BACKUP_TYPE=$1
if [ "${BACKUP_TYPE}" = "local" ];then
  backup_environment_check
  clone_backup_local
  his_backup_clean
elif [ "${BACKUP_TYPE}" = "remote" ];then
  backup_environment_check
  remote_backup_environment_check
  clone_backup_remote
  his_backup_clean
elif [ "${BACKUP_TYPE}" = "addcron" ] && [ $2 ];then
  backup_environment_check
  add_job_crontab "${SCRIPT_DIR}/backup_clone.sh " && echo -e "\033[32m *****add crontab success***** \033[0m"
  cat /etc/crontab
else
  printf "Usage:
      bash clone_backup.sh local                  本地备份
      bash clone_backup.sh remote                 远程备份
      bash clone_backup.sh addcron {local|remote} 添加定时任务,默认为每天凌晨2点55分执行备份,有需求自行修改\n"
  exit 1
fi

