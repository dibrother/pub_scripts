#!/bin/bash
set -e
NOW_TO_SOURCE_IPADDR=$1
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


check_params_basic(){
  if [ ! $SCRIPT_DIR ] || [ ! $MYSQL_DATA_DIR ] || [ ! $MYSQL_PKG ] || [ ! $MYSQL_PORT ] || [ ! $MEMORY_ALLLOW_GB ] || [ ! ${INIT_PASSWORD} ] || [ ! $IPADDR ];then
    print_message "[Error]" "传入指令参数不全，请检查 ./config/user.conf 文件"
    exit 1
  fi
}

rejoin_to_slave(){
  # 重新加入集群
  MYSQL_STATUS=`systemctl status mysqld${MYSQL_PORT}.service |grep "active (running)"|wc -l`
  if [ $MYSQL_STATUS -gt 0 ];then
    print_message "Note" "MySQL已启动..."
    print_message "Note" "新旧GTID确认比对..."
    OLD_SERVER_UUID=`$MYSQL_BIN_DIR -uroot -p"${INIT_PASSWORD}" -S $SOCKET_DIR -e "select @@server_uuid uid\G"|grep uid:|awk '{print $2}'`
    OLD_GTIDS=`$MYSQL_BIN_DIR -uroot -p"${INIT_PASSWORD}" -S $SOCKET_DIR -e "show master status;"|grep $OLD_SERVER_UUID|awk '{print $3}'`
    NEW_GTIDS=`$MYSQL_BIN_DIR -u${REPL_USER} -p"${REPL_PASSWORD}" -h${NOW_TO_SOURCE_IPADDR} -P${MYSQL_PORT}  -e "show master status;"|grep $OLD_SERVER_UUID|awk '{print $3}'`
    # echo "$MYSQL_BIN_DIR -u${REPL_USER} -p\"${REPL_PASSWORD}\" -h${NOW_TO_SOURCE_IPADDR} -P${MYSQL_PORT}  -e \"show master status;\"|grep $OLD_SERVER_UUID|awk '{print $3}'"
    ARRAY_OLD_GTIDS=(${OLD_GTIDS//,\\n/ })
    ARRAY_NEW_GTIDS=(${NEW_GTIDS//,\\n/ })
    #echo "-------OLD_GTIDS---------- $OLD_GTIDS"
    #echo "-------NEW_GTIDS---------- $NEW_GTIDS"
    for GTID_OLD in ${ARRAY_OLD_GTIDS[@]}
    do
      DTL_GTID=`echo ${GTID_OLD%:*}`
      if [[ $OLD_SERVER_UUID = $DTL_GTID ]];then
        OLD_GTID=$GTID_OLD
      fi
    done
    for GTID_NEW in ${ARRAY_NEW_GTIDS[@]}
    do
      DTL_GTID=`echo ${GTID_NEW%:*}`
      if [[ $OLD_SERVER_UUID = $DTL_GTID ]];then
        NEW_GTID=$GTID_NEW
      fi
    done
    #echo "-----------------OLD_GTID----------  $OLD_GTID"
    #echo "-----------------NEW_GTID----------  $NEW_GTID"
    if [[ ${OLD_GTID} < ${NEW_GTID} ]] || [[ ${OLD_GTID} = ${NEW_GTID} ]];then
      print_message "Note" "配置主从关系，主为：${NOW_TO_SOURCE_IPADDR}"
      cd $SCRIPT_DIR
      ./rejoin_change_master.sh "$MYSQL_BIN_DIR" "root" ${INIT_PASSWORD} "$MYSQL_PORT" "$SOCKET_DIR" "$NOW_TO_SOURCE_IPADDR" "$MYSQL_PORT" "$REPL_USER" ${REPL_PASSWORD} ${MYSQL_VERSION}
    else
      print_message "Error" "当前节点GTID值比主节点的大，不能作为从库加入，请手动检查..."
    fi
  else
    print_message "Error" "MySQL未启动，请先启动MySQL服务..."
    exit 1
  fi
}


if [ $NOW_TO_SOURCE_IPADDR ];then
  #加载配置文件
  source ./config/user.conf

  BASE_DIR='/usr/local'
  DATA_DIR=$MYSQL_DATA_DIR/mysql$MYSQL_PORT/data
  SOCKET_DIR=$DATA_DIR/mysql.sock
  MYSQL_BIN_DIR=$BASE_DIR/mysql/bin/mysql
  MYSQL_VERSION=`echo ${MYSQL_PKG##*/}|awk -F "-" '{print $2}'`
  MYSQL_LARGE_VERSION=`echo ${MYSQL_VERSION%.*}`
  
  check_params_basic 
  rejoin_to_slave
else
  printf "Usage: bash rejoin_to_slave.sh 主节点IP\n       如:./rejoin_to_slave.sh 192.168.66.161\n"
  exit
fi

# rejoin_to_slave
