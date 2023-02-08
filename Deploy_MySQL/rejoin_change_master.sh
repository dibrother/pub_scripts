#!/bin/bash
set -e
# 有创建用户权限的 用户名、密码、端口、SOCKET
# 需要创建的 用户名、密码、端口、SOCKET
MYSQL_CMD_DIR=$1
LOGIN_USER=$2
LOGIN_PASSWORD=$3
LOGIN_PORT=$4
LOGIN_SOCKET=$5
SOURCE_HOST=$6
SOURCE_PORT=$7
SOURCE_USER=$8
SOURCE_PASSWORD=$9
MYSQL_VERSION=${10}

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
  if [ ! $MYSQL_CMD_DIR ] || [ ! $LOGIN_USER ] || [ ! ${LOGIN_PASSWORD} ] || [ ! $LOGIN_PORT ] || [ ! $LOGIN_SOCKET ] || [ ! $SOURCE_HOST ] || [ ! $SOURCE_PORT ] || [ ! $SOURCE_USER ] || [ ! ${SOURCE_PASSWORD} ];then
    print_message "[Error]" "change master 指令参数不全，请检查"
    exit 1
  fi
}


change_master(){
  print_message "Note" "建立主从关系，目标主库地址为：$SOURCE_HOST"
  if [[ $MYSQL_VERSION > "8.0.25" ]];then
    /usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "STOP REPLICA;RESET REPLICA ALL;CHANGE REPLICATION SOURCE TO SOURCE_HOST = '$SOURCE_HOST',SOURCE_PORT = $SOURCE_PORT,SOURCE_USER = '$SOURCE_USER',SOURCE_PASSWORD = '${SOURCE_PASSWORD}',SOURCE_AUTO_POSITION = 1,MASTER_SSL = 1;START REPLICA;"
  else
    /usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "STOP SLAVE;RESET SLAVE ALL;CHANGE MASTER TO MASTER_HOST = '$SOURCE_HOST',MASTER_PORT = $SOURCE_PORT,MASTER_USER = '$SOURCE_USER',MASTER_PASSWORD = '${SOURCE_PASSWORD}',MASTER_AUTO_POSITION = 1;START SLAVE;"
  fi
  REPLICA_STATUS=`/usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "show slave status\G"|grep -E "Slave_IO_Running:|Slave_SQL_Running:"|wc -l`
  if [ $REPLICA_STATUS -eq 2 ];then
    print_message "Note" "主从关系建立成功"
  else
    print_message "Note" "主从关系建立失败,请检查"
    exit 1
  fi
}

set_read_only(){
  print_message "Note" "将当前从库设置为只读(read_only=1,super_read_only=1)"
  /usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "set global read_only=1;set global super_read_only=1;"
  print_message "Note" "当前从库已设置为只读"
}

set_rpl_semi_sync_enable(){
  print_message "Note" "设置从库相关参数(rpl_semi_sync_master_enabled=0,rpl_semi_sync_slave_enabled=1)"
  if [[ $MYSQL_VERSION > "8.0.25" ]];then
    /usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "set global rpl_semi_sync_source_enabled=0;set global rpl_semi_sync_replica_enabled=1;"
  else
    /usr/local/mysql/bin/mysql -u $LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "set global rpl_semi_sync_master_enabled=0;set global rpl_semi_sync_slave_enabled=1;"
  fi
  print_message "Note" "当前从库rpl_semi_sync_master_enabled,pl_semi_sync_slave_enabled 已设置"
}

check_params
set_rpl_semi_sync_enable
change_master
set_read_only
