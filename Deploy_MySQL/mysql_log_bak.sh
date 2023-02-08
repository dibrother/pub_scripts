#!/bin/bash
set -e

## 从远程备份机去MySQL主机拉取general_log并在本地压缩存储
# 需要远程备份机做对各MySQL的登陆免密
## 需要创建 MySQL 用户  'xxx'@'127.0.0.1'
## 授权 SUPER 以用于 set global ,8.0可使用 SYSTEM_VARIABLES 权限

BAK_TIME=`date +"%Y%m%d%H%M%S"`

######### 源端信息 ###############
MYSQL_USER="baklog_user"
MYSQL_PWD="123456"
MYSQL_HOST_IP="192.168.66.166"
MYSQL_PORT=3312
LOG_DIR="/data/mysql3312/data"
LOG_NAME="general.log"
LOCAL_DIR="/data/general_bak"
SSH_USER=root
SSH_PORT=22
#####  无需更改 ####
GENERAL_LOG=${LOG_DIR}/${LOG_NAME}
GENERAL_BAK_NAME=${LOG_NAME}.${BAK_TIME}
GENERAL_LOG_BAK=${LOCAL_DIR}/${GENERAL_BAK_NAME}
###################

######### 备份端信息 ###############
BACK_DIR="/data/general_bak/166"
BACK_LOG_DIR="/data/general_bak/166/log"
SAVE_DAYS=180



env_check(){
  if [ ! ${MYSQL_USER} ] || [ ! ${MYSQL_PWD} ] ||[  ! ${MYSQL_HOST_IP} ] || [ ! ${MYSQL_PORT} ] || [ ! ${SAVE_DAYS} ];then
    echo "参数配置信息有误,请检查..."
    exit 1
  fi
 
  if [ ! -d ${BACK_DIR} ] || [ ! -d ${BACK_LOG_DIR} ];then
    echo "`date +"%F %T"` 备份存储路径不存在,创建备份存储路径..."
    mkdir -p ${BACK_LOG_DIR}
  fi
}

general_bak(){
  MYSQL_STATUS=`/usr/local/mysql/bin/mysqladmin -h${MYSQL_HOST_IP} -u${MYSQL_USER} -p"${MYSQL_PWD}" -P${MYSQL_PORT} ping|grep 'mysqld is alive'|wc -l`
if [ ${MYSQL_STATUS} -eq 1 ];then
  IS_DIR_RESTLT=$(ssh -P${SSH_PORT} ${SSH_USER}@${MYSQL_HOST_IP} "if test -d ${LOCAL_DIR};then echo "1"; else echo "0"; fi")
  if [ ${IS_DIR_RESTLT} = "1" ];then
    /usr/local/mysql/bin/mysql -h${MYSQL_HOST_IP} -u${MYSQL_USER} -p"${MYSQL_PWD}" -P${MYSQL_PORT} -e "SET GLOBAL general_log = 'OFF';"
    ssh ${SSH_USER}@${MYSQL_HOST_IP} -P${SSH_PORT} "mv ${GENERAL_LOG} ${GENERAL_LOG_BAK}"
    /usr/local/mysql/bin/mysql -h${MYSQL_HOST_IP} -u${MYSQL_USER} -p"${MYSQL_PWD}" -P${MYSQL_PORT} -e "SET GLOBAL general_log = 'ON';"
  else
    echo "`date +"%F %T"` 日志文件 ${GENERAL_LOG} 不存在,请检查!"
    exit 1
  fi
else
   echo "`date +"%F %T"` MySQL未运行,请检查!"
   exit 1
fi
}

remote_get(){
  echo "`date +"%F %T"` 进行scp远程获取日志存储到本地并压缩"
  IS_DIR_RESTLT=$(ssh -P${SSH_PORT} ${SSH_USER}@${MYSQL_HOST_IP} "if test -d ${LOCAL_DIR};then echo "1"; else echo "0"; fi")
  if [ ${IS_DIR_RESTLT} = "1" ];then
    #echo "scp ${SSH_USER}@${MYSQL_HOST_IP} -P${SSH_PORT} ${GENERAL_LOG_BAK} ${BACK_DIR}"
    scp -P${SSH_PORT} ${SSH_USER}@${MYSQL_HOST_IP}:${GENERAL_LOG_BAK} ${BACK_DIR}
    echo "`date +"%F %T"` 日志传输完成"
    cd ${BACK_DIR}
    echo "`date +"%F %T"` 进行压缩..."
    tar zcf ${GENERAL_BAK_NAME}.tar.gz ${GENERAL_BAK_NAME}
    echo "`date +"%F %T"` 压缩完成"
    if [ -a ${GENERAL_BAK_NAME}.tar.gz ];then
      echo "`date +"%F %T"` 删除被压缩原文件"
      rm -f ${GENERAL_BAK_NAME}
    fi
  else
    echo "`date +"%F %T"` ${BACK_DIR}/${GENERAL_BAK_NAME}.tar.gz 文件不存在"
    exit 1
  fi
}

# 删除远程文件
remote_rm(){
  echo "`date +"%F %T"` 删除远程MySQL的general备份文件"
  IS_FILE_RESTLT=$(ssh -P${SSH_PORT} ${SSH_USER}@${MYSQL_HOST_IP} "if test -f ${GENERAL_LOG_BAK};then echo "1"; else echo "0"; fi") 
  if [ ${IS_FILE_RESTLT} = "1" ];then
    ssh -P${SSH_PORT} ${SSH_USER}@${MYSQL_HOST_IP} "rm -f ${GENERAL_LOG_BAK}"
    echo "`date +"%F %T"` 删除完成"
  else
    echo "`date +"%F %T"` 远程文件不存在"
    exit 1
  fi
}

history_clean(){
 echo "`date +"%F %T"` 开始清理${SAVE_DAYS}天前的文件"
 if [ -d ${BACK_DIR} ] && [ -d ${BACK_LOG_DIR} ];then
  find ${BACK_DIR} -type f -name "${LOG_NAME}*.tar.gz" -mtime +${SAVE_DAYS} | xargs rm -f
  find ${BACK_LOG_DIR} -type f -name "*.log" -mtime +${SAVE_DAYS} | xargs rm -f
 else
  echo "`date +"%F %T"` 被清理文件路径不存在!"
  exit 1
 fi 
}

env_check
general_bak
remote_get
remote_rm
history_clean
