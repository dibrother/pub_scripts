#!/bin/bash
#set -e
####################### 简介 ###########################3
# 作者:杨大仙
# 使用方法
# ● 修改脚本相关配置
# ● 支持本地备份、远程备份（需要对远程机做免密）、钉钉告警
# ● 可以执行  ./xtra_bak add_cron /app/scrpits/xtra_bak.sh 添加定时任务cron，默认时间点为每天凌晨2:55进行备份

# 获取脚本绝对路径,需要与dingtaik_send在一个目录下
SCRIPT_DIR=$(cd `dirname $0`; pwd)
########################  xtraback信息配置[必须根据环境修改]  ##########################
XTRABACKUP_PATH=/usr/bin/xtrabackup
BACKUP_SAVE_DAYS=7
BACKUP_DIR=/data/backup
BACKUP_PREFIX_NAME="xtra_full"
## 压缩并发进程与备份并发进程数，默认都为2
COMPRESS_THREADS=2
PARALLEL=2

BACKUP_LOG=$BACKUP_DIR/log
BACKUP_DATETIME=`date +%Y%m%d%H%M%S`

########################  获取系统信息[必须根据环境修改]  ###############################
LOCAL_DISK_CMD=`df -Th|grep centos-root|awk '{print $6}'`

########################  Mysql备份用户信息[必须根据环境修改]  ##########################
MYSQL_CNF_DIR=/data/mysql3312/my3312.cnf
BACKUP_USER=databak
BACKUP_PWD='123456'
MYSQL_SOCK_DIR=/data/mysql3312/data/mysql.sock

########################  远程传输配置，使用远程需要配置免密[可选修改]  ##########################
## 远程备份开关，默认0
REMOTE_BACKUP_SWITCH=0
REMOTE_TITLE="数据库远程备份"
REMOTE_USER=root
REMOTE_HOST=192.168.1.27
REMOTE_BACKUP_DIR=/data/backup
REMOTE_DISK_USE_CMD="df -Th|grep centos-root|awk '{print \$6}'"
########################  dingding通知配置[可选修改]  ##########################
DINGDING_SWITCH=0
MSG_TITLE="数据库备份"
WEBHOOK_URL='https://oapi.dingtalk.com/robot/send?access_token=ed21b5e3208ec6c261292240c599307b1ce22418a44cbe2f9474468b8d526352'
SECRET='SECe611844ed55ddc610a3c88134722e074ac3c8420a4d15a100fef7a191eb95b88'
# 支持 text/markdown
SEND_TYPE="markdown"
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=""
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=""

# 环境检查
backup_environment_check(){
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 进行备份前预检查"
	if [ ! -x ${XTRABACKUP_PATH} ];then
          echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] xtrabackup 命令不存在，请检查！"
          exit 1 
	fi

	if [ ! -d ${BACKUP_DIR} ] || [ ! -e ${MYSQL_CNF_DIR} ] || [ ! -e ${MYSQL_SOCK_DIR} ];then
          echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 备份或MySQL相关参数路径配置不正确，请检查！"
          exit 1
	fi

	if [ ! -d ${BACKUP_LOG} ];then
          echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 创建日志文件目录"
          mkdir -p $BACKUP_LOG
	fi

	if [ ${REMOTE_BACKUP_SWITCH} -eq 1 ];then
          if [ ! ${REMOTE_USER} ] || [ ! ${REMOTE_HOST} ] || [ ! ${REMOTE_BACKUP_DIR} ];then
            echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 远程参数配置缺漏，请检查！"
            exit 1
          fi

          # ssh 免密检查，到远程机需要配置免密
          SSH_FREE_STATUS=`ssh ${REMOTE_HOST} -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no "date" |wc -l`
          if [ $SSH_FREE_STATUS -lt 1 ];then
            echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 免密验证[${REMOTE_HOST}]失败,请检查免密配置!"
            exit 1
          fi
        elif [ ${REMOTE_BACKUP_SWITCH} != 0 ];then
          echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] REMOTE_BACKUP_SWITCH 参数请传入值 0 或 1"
          exit 1
	fi
        
        if [[ ${DINGDING_SWITCH} -eq 1 ]];then
          dingding_test
        fi
	echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 预检查完成"
}

dingding_test(){
  local DING_MSG="钉钉连通性测试"
  local DING_STATUS=`dingding_note "通知" "${DING_MSG}"`
  if [ ${DING_STATUS} != '{"errcode":0,"errmsg":"ok"}' ];then
    echo "钉钉消息发送失败,请检查! 钉钉命令为 dingding_note \"通知\" \"${DING_MSG}\""
  fi
}

# 流式压缩备份-本地 --ftwrl-wait-timeout=
xbstream_compress_backup_local(){
    local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
    echo "${BAKUP_BEGIN_TIME} [Note] 开始进行本地备份"
    ${XTRABACKUP_PATH} --defaults-file=${MYSQL_CNF_DIR} --socket=${MYSQL_SOCK_DIR} --user=databak --password=123456 --backup --stream=xbstream --target-dir=${BACKUP_DIR} --ftwrl-wait-timeout=300 --compress --compress-threads=${COMPRESS_THREADS} --parallel=${PARALLEL} > ${BACKUP_DIR}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb 2>${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.log
    local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"` 

    check_backup_status
    
    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local BACKUP_FILE_SIZE=`ls -lh ${BACKUP_DIR}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb|awk '{print $5}'`
      local DING_MSG="**通知内容:**\n* 备份文件:${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb\n* 文件大小：${BACKUP_FILE_SIZE}\n* 备份目录：${BACKUP_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      if [ ${BACKUP_STATUS} -eq 1 ];then
        dingding_note "通知" "${DING_MSG}"
      else
        dingding_note "异常" "${DING_MSG}"     
      fi
    fi   
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 本地备份完成"
}

# 流式压缩备份-远程
xbstream_compress_backup_remote(){
    local BAKUP_BEGIN_TIME=`date +"%Y-%m-%d %H:%M:%S"`
    echo "${BAKUP_BEGIN_TIME} [Note] 开始进行远程备份"
    ${XTRABACKUP_PATH} --defaults-file=${MYSQL_CNF_DIR} --socket=${MYSQL_SOCK_DIR} --user=databak --password=123456 --backup --stream=xbstream --target-dir=${BACKUP_DIR} --ftwrl-wait-timeout=300 --compress --compress-threads=${COMPRESS_THREADS} --parallel=${PARALLEL} 2>${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.log| ssh ${REMOTE_USER}@${REMOTE_HOST} "cat - > ${REMOTE_BACKUP_DIR}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb"
    local BAKUP_END_TIME=`date +"%Y-%m-%d %H:%M:%S"`
    
    check_backup_status

    if [[ ${DINGDING_SWITCH} -eq 1 ]];then
      local LOCAL_DISK_USE=${LOCAL_DISK_CMD}
      local REMOTE_DISK_USE=`ssh ${REMOTE_USER}@${REMOTE_HOST} "${REMOTE_DISK_USE_CMD}"`
      local BACKUP_FILE_SIZE_CMD="ls -lh ${BACKUP_DIR}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb|awk '{print \$5}'"
      local BACKUP_FILE_SIZE=`ssh ${REMOTE_USER}@${REMOTE_HOST} "${BACKUP_FILE_SIZE_CMD}"`
      local DING_MSG="**通知内容:**\n* 本地备份目录：${BACKUP_DIR}\n* 磁盘使用率：${LOCAL_DISK_USE}\n* 远程备份主机：${REMOTE_HOST}\n* 远程备份文件:${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb\n* 远程备份大小：${BACKUP_FILE_SIZE}\n* 远程备份目录：${REMOTE_BACKUP_DIR}\n* 远程磁盘使用率：${REMOTE_DISK_USE}\n* 备份开始时间:${BAKUP_BEGIN_TIME}\n* 备份结束时间:${BAKUP_END_TIME}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
      if [ ${BACKUP_STATUS} -eq 1 ];then
        dingding_note "通知" "${DING_MSG}"
      else
        dingding_note "异常" "${DING_MSG}"
      fi
    fi
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 远程备份完成"
}

# 清除历史备份
his_backup_clean()
{	
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 开始清理历史备份"
    if [ -d ${BACKUP_DIR} ];then
      find ${BACKUP_DIR} -type f -name '${BACKUP_PREFIX_NAME}_*.xb' -mtime +${BACKUP_SAVE_DAYS} -exec rm -rf {} \;
      find ${BACKUP_LOG} -type f -name '${BACKUP_PREFIX_NAME}_*.log' -mtime +${BACKUP_SAVE_DAYS} -exec rm -rf {} \;
    fi
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 清理历史备份清理完成"
}

# 钉钉信息发送
## $1 通知/异常
## $2 发送信息
dingding_note(){
  if [[ ${DINGDING_SWITCH} -eq 1 ]];then
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 发送钉钉通知..."
    if [[ $1 == "通知" ]]; then
      local color="#006600"
    else
      local color="#FF0033"
    fi
    local DING_MESSAGE="**[<font color=${color}>$1</font>]** \n \n--- \n$2"
    if [[ ${IS_AT_ALL} ]];then
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_all
    elif [[ ${AT_MOBILES} ]];then
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}" -at_mobiles ${AT_MOBILES}
    else
      ${SCRIPT_DIR}/dingtalk_send -url "${WEBHOOK_URL}" -secert "${SECRET}" -title "${MSG_TITLE}" -type "${SEND_TYPE}" -msg "${DING_MESSAGE}"
    fi
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 钉钉通知完成..."
  fi
}

do_backup(){
    # 检查后台是否有xtrabackup进程
    local XTRA_PROCESS=`ps -ef | grep -v "grep" | grep ${XTRABACKUP_PATH} | wc -l`
    if [[ ${XTRA_PROCESS} -eq 0 ]];then
      backup_environment_check
      his_backup_clean
      if [[ ${REMOTE_BACKUP_SWITCH} -eq 1 ]];then
        xbstream_compress_backup_remote
      else
        xbstream_compress_backup_local
      fi
    else
      echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 已有备份正在运行"
      exit 1 
    fi
}

# 检查备份是否成功
check_backup_status(){
  BACKUP_STATUS=`tail -5 ${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.log |grep "completed OK"|wc -l`
  if [ ${BACKUP_STATUS} -eq 1 ];then
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Note] 备份[${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb]成功"
  else
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 备份[${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb]失败"
    echo "`date +"%Y-%m-%d %H:%M:%S"` [Error] 日志文件为 ${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.log"
    local DING_MSG="**<font color=#FF0033>备份失败,请检查!!!</font>**\n* 备份文件:${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.xb\n* 备份目录：${BACKUP_DIR}\n* 日志文件:${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}.log\n* 日志目录:${BACKUP_LOG}\n---\n**通知时间:** \n \n`date '+%Y-%m-%d %H:%M:%S'`"
    dingding_note "异常" "${DING_MSG}"
    exit 1
  fi 
}

# 添加定时任务
add_job_crontab()
{
  echo $1
  cat >> /etc/crontab << EOF
# 每天凌晨2点55分执行备份
55 02 * * * root /bin/bash $1 > ${BACKUP_LOG}/${BACKUP_PREFIX_NAME}_${BACKUP_DATETIME}_script.log 2>&1
EOF
}

if [[ $1 == "add_cron" ]]; then
  if [[ ! $2 ]];then
    echo "缺失脚本路径,使用示例: ./xtra_bak add_cron /app/script/xtra_bak.sh"
  else
    add_job_crontab $2 && echo -e "\033[32m *****add crontab success***** \033[0m"
    cat /etc/crontab
  fi
else
  do_backup
fi
