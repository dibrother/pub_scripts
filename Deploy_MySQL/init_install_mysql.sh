#!/bin/bash
#set -e

MYSQL_DIR=$1
MYSQL_PKG=$2
MYSQL_PORT=$3
MEMORY_ALLLOW_GB=$4
INIT_PASSWORD=$5
MYCNF_DEFAULT=$6
IPADDR=$7

BASE_DIR='/usr/local'
DATA_DIR=$MYSQL_DIR/mysql$MYSQL_PORT/data
SOCKET_DIR=$DATA_DIR/mysql.sock
MYSQLX_SOCKET_DIR=$DATA_DIR/mysqlx.sock
MYSQL_VERSION=`echo ${MYSQL_PKG##*/}|awk -F "-" '{print $2}'`
MYSQL_LINK_DIR=$BASE_DIR/mysql
MYSQL_UNCOMPRESS=`echo ${MYSQL_PKG##*/}|awk -F ".tar" '{print $1}'`
MYCNF_DIR=$MYSQL_DIR/mysql$MYSQL_PORT/my$MYSQL_PORT.cnf
# 默认X端口就在源端口加100
MYSQLX_PORT=`expr $MYSQL_PORT + 100`
# 默认MySQL管理端口,源默认值为 33062,这边修改为默认为 33162
MYSQL_ADMIN_PORT=`expr $MYSQL_PORT + 200`
PID_FILE=$DATA_DIR/mysqld.pid
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
  if [ ! $MYSQL_DIR ] || [ ! $MYSQL_PKG ] || [ ! $MYSQL_PORT ] || [ ! $MEMORY_ALLLOW_GB ] || [ ! ${INIT_PASSWORD} ] || [ ! $MYCNF_DEFAULT ] || [ ! $IPADDR ];then
    print_message "[Error]" "init_mysql_install 指令参数不全，请检查"
    exit 1
  fi
}

optimize_system(){
  print_message "Note" "检测是否使用大页..."
  USE_HUGEPAGE_NUMS=`cat /proc/meminfo | grep -i huge|grep HugePages_Total|awk '{print $2}'`
  if [ $USE_HUGEPAGE_NUMS -gt 0 ];then
    print_message "Warning" "使用了大页,若使用大页会占用内存!请确认!!!"
  fi

  print_message "Note" "检测是否使用了CPU节能模式..."
  CPU_POWER_STATUS=`cpupower frequency-info --policy|grep powersave|wc -l`
  if [ $CPU_POWER_STATUS -gt 0 ];then
    print_message "Warning" "服务器使用了CPU节能模式,会导致性能下降,请检查!!!"
  fi

  print_message "Warning" "可执行 cat /sys/block/sd[bc]/queue/scheduler 检查磁盘调度设置,若为SSD磁盘的话,建议设置为 noop ,其余的设置为 deadline"
}

# 卸载系统自带 mariadb
uninstall_mariadb(){
  print_message "Note" "检测是否安装 mariadb..."
  IS_MARIADB=`rpm -qa|grep mariadb-libs|wc -l`
  if [ $IS_MARIADB -gt 0 ];then
    MARIADB=`rpm -qa|grep mariadb-libs`
    rpm -e --nodeps $MARIADB
    print_message "Warning" "卸载默认安装的mariadb"
  else
    print_message "Note" "mariadb 未安装或已被卸载"
  fi
}

# 安装前环境准备
check_install_env(){
  ## 检查安装所需文件是否存在
  [ ! -f ./soft/$MYSQL_PKG ] && print_message "Error" "MySQL安装包不存在,当前传入路径为：$MYSQL_PKG" && exit 1 || print_message "Note" "检测MySQL安装包存在，路径为：$MYSQL_PKG"
  [ ! -f $MYCNF_DEFAULT ] && print_message "Error" "my.cnf默认配置文件不存在,当前传入路径为：$MYCNF_DEFAULT" && exit 2 || print_message "Note" "my.cnf默认配置文件存在，路径为：$MYCNF_DEFAULT"
  
  if [ -f /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service ];then
    print_message "Error" "/usr/lib/systemd/system/mysqld${MYSQL_PORT}.service 已被占用,请检查! "
    exit 3
  else
    print_message "Note" "检查 /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service 是否被占用"
  fi
 
  #[ "$(ls -A /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service)" ] && print_message "Error" "/usr/lib/systemd/system/mysqld${MYSQL_PORT}.service 已被占用,请检查! " && exit 3 ||print_message "Note" "检查 /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service 是否被占用"
  
  ## 检查libaio依赖
  print_message "Note" "检测环境依赖包[libaio]..."
  IS_LIBAIO=`rpm -qa|grep libaio|grep x86_64|wc -l`
  [ $IS_LIBAIO -eq 0 ] && print_message "Error" "依赖包 libaio 不存在" && exit 3 || print_message "Note" "环境依赖包[libaio]已安装"
  ## 检查端口限制
  if [[ ${MYSQL_PORT} -gt 65535 ]] || [[ ${MYSQLX_PORT} -gt 65535 ]];then
    print_message "Error" "端口设置超出65535限制,请重新设置端口!当前端口值 MySQL port:${MYSQL_PORT},MySQLX port:${MYSQLX_PORT}"
    exit 1
  fi

  ## 检查端口占用
  print_message "Note" "检测端口${MYSQL_PORT}是否被占用..."
  IS_PORT=`ss -ntpl | grep -w $MYSQL_PORT|wc -l`
  [ $IS_PORT -gt 0 ] && print_message "Error" "MySQL端口${MYSQL_PORT}已被占用" && exit 4 || print_message "Note" "MySQL端口${MYSQL_PORT}可用"

  IS_MYSQLX_PORT=`ss -ntpl | grep -w $MYSQLX_PORT|wc -l`
  [ $IS_MYSQLX_PORT -gt 0 ] && print_message "Error" "MySQLX端口${MYSQLX_PORT}已被占用" && exit 5 || print_message "Note" "MySQLX端口${MYSQLX_PORT}可用"
  
  IS_MYSQL_ADMIN_PORT=`ss -ntpl | grep -w $MYSQL_ADMIN_PORT|wc -l`
  [ $IS_MYSQL_ADMIN_PORT -gt 0 ] && print_message "Error" "MySQL Admin管理端口${MYSQL_ADMIN_PORT}已被占用" && exit 5 || print_message "Note" "MySQL Admin管理端口${MYSQL_ADMIN_PORT}可用"

  ## 检查并创建用户组和用户
  print_message "Note" "检测mysql用户与组..."
  IS_MYSQL_GROUP=`grep -w "mysql" /etc/group|wc -l`
  [ $IS_MYSQL_GROUP -eq 0 ] && groupadd mysql && print_message "Note" "mysql用户组创建成功" || print_message "Warning" "mysql用户组已存在"

  IS_MYSQL_USER=`grep -w "mysql" /etc/passwd|wc -l`
  [ $IS_MYSQL_USER -eq 0 ] && useradd  -g mysql -s /bin/nologin mysql && print_message "Note" "mysql用户创建成功" || print_message "Warning" "mysql用户已存在"

  ## 检查并创建数据路径
  print_message "Note" "检查数据目录..."
  if [ -d $DATA_DIR ];then
    if [ "$(ls -A $DATA_DIR)" ];then
      print_message "Error" "目录$DATA_DIR 已存在且不为空"
      exit 5
    else
      print_message "Warning" "目录$DATA_DIR 已存在"
    fi
  else
    mkdir -p $DATA_DIR
    print_message "Note" "创建数据目录：$DATA_DIR"
  fi
}


## 初始化MySQL用户，修改初始密码，若类型指定为master，则会创建一个bd_repl用户
change_init_password(){
    print_message "Note" "修改MySQL初始化密码"
    ## 初始化密码 
    TEMP_PASWORD=`cat $DATA_DIR/error.log |grep 'A temporary password'|awk -F " " '{print $(NF)}'`
    $MYSQL_LINK_DIR/bin/mysqladmin -uroot -p"$TEMP_PASWORD" -P$MYSQL_PORT -S $SOCKET_DIR password "${INIT_PASSWORD}"
    print_message "Note" "修改初始密码成功"
}

# 创建用户
create_user(){
  CREATE_USER=$1
  CREATE_PASSWORD=$2
  CREATE_IP_SEGMENT=$3
  CREATE_USER_PRIVS=$4
  ./create_user.sh  $MYSQL_LINK_DIR/bin/mysql root "${INIT_PASSWORD}" $MYSQL_PORT $SOCKET_DIR $CREATE_USER "${CREATE_PASSWORD}" "$CREATE_IP_SEGMENT" $CREATE_USER_PRIVS
}

# 安装
install_mysql(){
  # 优化系统相关项
  optimize_system

  # 卸载 mariadb
  uninstall_mariadb

  # 授权目录
  print_message "Note" "对目录进行授权"
  chown -R mysql.mysql $DATA_DIR

  # 解压
  if [ -d $BASE_DIR/$MYSQL_UNCOMPRESS ];then
    print_message "Warning" "$MYSQL_UNCOMPRESS 文件已存在"
  else
    print_message "Note" "开始解压缩，可能需要花费几分钟，请耐心等待"
    mkdir -p $BASE_DIR/$MYSQL_UNCOMPRESS
    tar xf ./soft/$MYSQL_PKG -C $BASE_DIR/$MYSQL_UNCOMPRESS --strip-components 1
  fi

  ## 创建软链
  print_message "Note" "检查配置软链..."
  if [ -L $MYSQL_LINK_DIR ];then
    is_link=`ls -l $MYSQL_LINK_DIR|grep -w $MYSQL_UNCOMPRESS|wc -l`
    if [[ $is_link -eq 0 ]];then
      print_message "Warning" "软链已存在,原软链为 : `ls -l $MYSQL_LINK_DIR`"
      unlink $MYSQL_LINK_DIR
      ln -s $BASE_DIR/$MYSQL_UNCOMPRESS $MYSQL_LINK_DIR
      print_message "Warning" "当前软链替换为 : `ls -l $MYSQL_LINK_DIR`"
    else
      print_message "Warning" "软链已存在"
    fi
  else
    ln -s $BASE_DIR/$MYSQL_UNCOMPRESS $MYSQL_LINK_DIR
    print_message "Note" "设置软链: `ls -l $MYSQL_LINK_DIR`"
  fi

  ## 设置环境变量,/etc/profile.d/mysql_set_env.sh ,脚本名称固定
  if [ ! -f /etc/profile.d/mysql_set_env.sh ];then
    echo "export PATH=$PATH:$MYSQL_LINK_DIR/bin" > /etc/profile.d/mysql_set_env.sh
    source /etc/profile.d/mysql_set_env.sh
    print_message "Note" "设置环境变量成功"
  else
    print_message "Warning" "环境变量已被设置"
  fi
  
  ## 配置my.cnf
  print_message "Note" "配置my.cnf"
  if [ -e $MYCNF_DIR ];then
  mv $MYCNF_DIR $MYCNF_DIR.`date +%Y%m%d%H%M%S`
    print_message "Warning" "my.cnf 配置文件已存在，源配置文件被重命名为 $MYCNF_DIR.`date +%Y%m%d%H%M%S`"
  fi
  
  ## 从默认配置复制参数文件my.cnf
  cp $MYCNF_DEFAULT $MYCNF_DIR
  # 替换路径
  sed -i 's#^datadir.*$#datadir = '$DATA_DIR'#' $MYCNF_DIR
  sed -i 's#^tmpdir.*$#tmpdir = '$DATA_DIR'#' $MYCNF_DIR
  sed -i 's#^socket.*$#socket = '$SOCKET_DIR'#' $MYCNF_DIR
  sed -i 's#^mysqlx_socket.*$#mysqlx_socket = '$MYSQLX_SOCKET_DIR'#' $MYCNF_DIR
  # 替换端口
  sed -i 's#^port.*$#port = '$MYSQL_PORT'#' $MYCNF_DIR
  sed -i 's#^mysqlx_port.*$#mysqlx_port = '$MYSQLX_PORT'#' $MYCNF_DIR
  sed -i 's#^admin_port.*$#admin_port = '$MYSQL_ADMIN_PORT'#' $MYCNF_DIR
  # 设置report
  sed -i 's/^#report_host=.*$/report_host='${IPADDR}'/' $MYCNF_DIR
  sed -i 's/^#report_port=.*$/report_port='${MYSQL_PORT}'/' $MYCNF_DIR
  # 替换server_id
  SERVER_ID=`echo "$IPADDR"|awk -F "." '{print $3$4}'`
  sed -i 's#^server_id.*$#server_id = '$SERVER_ID'#' $MYCNF_DIR
  # 设置 innodb_buffer_pool
  #INNODB_BUFFER_POOL_SIZE=`expr $MEMORY_ALLLOW_GB \* 1024 \* 65 / 100 / 128 / 8`
  
  if [ $MEMORY_ALLLOW_GB -le 1 ];then
    sed -i 's/^innodb_buffer_pool_size.*$/#innodb_buffer_pool_size = 4G/' $MYCNF_DIR  #小于1G的就直接使用默认值
  else
    INNODB_BUFFER_POOL_SIZE=`expr $MEMORY_ALLLOW_GB \* 1024 \* 60 / 100 / 128 / 8`
    sed -i 's/^innodb_buffer_pool_size.*$/innodb_buffer_pool_size = '$INNODB_BUFFER_POOL_SIZE'G/' $MYCNF_DIR
  fi
  
  # 根据内存大小调整相关的参数
  if [ $MEMORY_ALLLOW_GB -lt 4 ];then
    sed -i 's/^read_buffer_size/#&/' $MYCNF_DIR
    sed -i 's/^read_rnd_buffer_size/#&/' $MYCNF_DIR
    sed -i 's/^sort_buffer_size/#&/' $MYCNF_DIR
    sed -i 's/^join_buffer_size/#&/' $MYCNF_DIR
    sed -i 's/^bulk_insert_buffer_size/#&/' $MYCNF_DIR
    sed -i 's/^tmp_table_size/#&/' $MYCNF_DIR
    sed -i 's/^max_heap_table_size/#&/' $MYCNF_DIR
    sed -i 's/^binlog_cache_size.*$/binlog_cache_size = 2M/' $MYCNF_DIR
  elif [ $MEMORY_ALLLOW_GB -ge 4 ] && [ $MEMORY_ALLLOW_GB -lt 16 ];then
    sed -i 's/^read_buffer_size.*$/read_buffer_size = 2M/' $MYCNF_DIR
    sed -i 's/^read_rnd_buffer_size.*$/read_rnd_buffer_size = 2M/' $MYCNF_DIR
    sed -i 's/^sort_buffer_size.*$/sort_buffer_size = 2M/' $MYCNF_DIR
    sed -i 's/^join_buffer_size.*$/join_buffer_size = 2M/' $MYCNF_DIR
    sed -i 's/^bulk_insert_buffer_size.*$/bulk_insert_buffer_size = 16M/' $MYCNF_DIR
  fi


  ## 初始化
  cd $MYSQL_LINK_DIR
  print_message "Note" "初始化MySQL..."
  bin/mysqld --defaults-file=$MYCNF_DIR --initialize  --user=mysql

  ## 设置service 启动
  #cd $MYSQL_LINK_DIR
  #cp support-files/mysql.server /etc/init.d/mysqld
  add_systemd_mysql
  systemctl_reload

  ## 启动
  print_message "Note" "启动MySQL..."
  #$MYSQL_LINK_DIR/bin/mysqld_safe --defaults-file=$MYCNF_DIR --user=mysql > /dev/null &
  systemctl start mysqld${MYSQL_PORT}.service
  sleep 5
  MYSQL_STATUS=`systemctl status mysqld${MYSQL_PORT}.service |grep "active (running)"|wc -l`
  if [ $MYSQL_STATUS -gt 0 ];then
    create_tmp_sock
    print_message "Warning" "\033[33m 请执行 /etc/profile.d/mysql_set_env.sh 使环境变量生效 或 重新打开shell窗口 \033[0m"
    print_message "Note" "安装完成，MySQL已启动...   可使用 systemctl status mysqld${MYSQL_PORT}.service 进行查看状态 "
  else
    print_message "Error" "启动判断异常，错误日志路径：$DATA_DIR/error.log，错误信息如下："
    tail -100 $DATA_DIR/error.log
    exit 1
  fi
}

# 配置systemctl 启停脚本
add_systemd_mysql(){
print_message "Note" "配置systemd启停脚本..."
if [[ $MYSQL_VERSION > "8.0" ]];then
cat > /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service <<EOF
[Unit]
Description=MySQL Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=mysql
Group=mysql

# Have mysqld write its state to the systemd notify socket
Type=notify

# Disable service start and stop timeout logic of systemd for mysqld service.
TimeoutSec=0

ExecStart=$BASE_DIR/$MYSQL_UNCOMPRESS/bin/mysqld --defaults-file=$MYCNF_DIR \$MYSQLD_OPTS 

# Use this to switch malloc implementation
EnvironmentFile=-/etc/sysconfig/mysql

# Sets open_files_limit
LimitNOFILE = 10000

Restart=on-failure

RestartPreventExitStatus=1

# Set environment variable MYSQLD_PARENT_PID. This is required for restart.
Environment=MYSQLD_PARENT_PID=1

PrivateTmp=false
EOF
elif [[ $MYSQL_VERSION < "8.0" ]] && [[ $MYSQL_VERSION > "5.7" ]];then
cat > /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service <<EOF
[Unit]
Description=MySQL Server
Documentation=man:mysqld(7)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=mysql
Group=mysql

Type=forking

PIDFile=$PID_FILE

# Disable service start and stop timeout logic of systemd for mysqld service.
TimeoutSec=0

# Start main service
ExecStart=$BASE_DIR/$MYSQL_UNCOMPRESS/bin/mysqld --defaults-file=$MYCNF_DIR --daemonize  
--pid-file=$PID_FILE \$MYSQLD_OPTS 

# Use this to switch malloc implementation
EnvironmentFile=-/etc/sysconfig/mysql

# Sets open_files_limit
LimitNOFILE = 5000

Restart=on-failure

RestartPreventExitStatus=1

PrivateTmp=false
EOF
fi
chmod 644 /usr/lib/systemd/system/mysqld${MYSQL_PORT}.service
} 

systemctl_reload(){
  print_message "Note" "执行 systemctl daemon-reload..."
  systemctl daemon-reload 
}

create_tmp_sock(){
  print_message "Note" "创建 /tmp/mysql.sock 软链"
  if [ ! -f /tmp/mysql.sock ] && [ ! -L /tmp/mysql.sock ];then
    ln -s $SOCKET_DIR /tmp/mysql.sock
    print_message "Note" "软链 /tmp/mysql.sock 创建完成"
  else
    print_message "Warning" "/tmp/mysql.sock 已存在,请确认,需要正确登陆请使用 -S $SOCKET_DIR 登陆"
  fi
}


check_params
check_install_env
install_mysql
# 修改初始密码
change_init_password


