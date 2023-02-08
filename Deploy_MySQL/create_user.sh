#!/bin/bash
set -e

# 有创建用户权限的 用户名、密码、端口、SOCKET
# 需要创建的 用户名、密码、端口、SOCKET
MYSQL_CMD_DIR=$1
LOGIN_USER=$2
LOGIN_PASSWORD=$3
LOGIN_PORT=$4
LOGIN_SOCKET=$5
CREATE_USER=$6
CREATE_PASSWORD=$7
CREATE_USER_PRIVS=$8


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
  if [ ! "$MYSQL_CMD_DIR" ] || [ ! "$LOGIN_USER" ] || [ ! "${LOGIN_PASSWORD}" ] || [ ! "$LOGIN_PORT" ] || [ ! "$LOGIN_SOCKET" ] || [ ! "$CREATE_USER" ] || [ ! "${CREATE_PASSWORD}" ] || [ ! "$CREATE_USER_PRIVS" ];then
    print_message "Error" "创建用户传入参数不全，请检查"
    exit 1
  fi
}

create_user(){
  print_message "Note" "创建用户['$CREATE_USER']"
  echo "$MYSQL_CMD_DIR -u$LOGIN_USER -p\"${LOGIN_PASSWORD}\" -P$LOGIN_PORT -S $LOGIN_SOCKET -e \"create user '$CREATE_USER' identified by '$CREATE_PASSWORD';grant \"$CREATE_USER_PRIVS\" on *.* to '$CREATE_USER';\""
  $MYSQL_CMD_DIR -u$LOGIN_USER -p"${LOGIN_PASSWORD}" -P$LOGIN_PORT -S $LOGIN_SOCKET -e "create user '$CREATE_USER' identified by '${CREATE_PASSWORD}';grant $CREATE_USER_PRIVS on *.* to '$CREATE_USER';"
  print_message "Note" "用户['$CREATE_USER'@'$CREATE_IP_SEGMENT']创建完成"
}

check_params
create_user
