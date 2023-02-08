#!/bin/bash
set -e

## 安装包默认解压为 /usr/local/mysql

BASE_DIR='/usr/local'
MYSQL_LINK_DIR=$BASE_DIR/mysql
# root@localhost 的密码
ROOT_PASSWORD='123456'
ROOT_SOCKET=/data/mysql3312/data/mysql.sock

# 新的安装包绝对路径
NEW_VERSION_PKG_PATH=/opt/installMysql/soft/mysql-5.7.40-linux-glibc2.12-x86_64.tar.gz
MYSQL_NEW_VERSION=`echo $NEW_VERSION_PKG_PATH|awk -F - '{print $2}'`
NEW_MYCNF=/data/mysql3312/my3312.cnf
# 升级前是否需要备份下数据，数据量大会比较久
IS_NEED_BACKUP=0
NEED_BACKUP_DIR=''
# 是否从库
IS_SLAVE=0
# 是否强制更新
IS_UPGRADE_FORCE=0

# 如果是 service 方式启停的,直接去修改 up_start_mysql 等3个方法,否则service会报错
MYSQL_START_COMMAND='systemctl start mysqld3312'
MYSQL_STOP_COMMAND='systemctl stop mysqld3312'
MYSQL_RESTART_COMMAND='systemctl restart mysqld3312'

MYSQL_UNCOMPRESS=`echo ${NEW_VERSION_PKG_PATH##*/}|awk -F ".tar" '{print $1}'`
DATA_TIME=`date +%Y%m%d%I%M%S`


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

check_params(){
	if [ ! $BASE_DIR ] || [ ! $MYSQL_LINK_DIR ] || [ ! ${ROOT_PASSWORD} ] || [ ! $ROOT_SOCKET ] || [ ! $NEW_VERSION_PKG_PATH ] || [ ! $NEW_MYCNF ] || [ ! $IS_NEED_BACKUP ] || [ ! $IS_SLAVE ]|| [ ! $IS_UPGRADE_FORCE ];then
		print_message "Error" "指令参数传入不全，请检查！"
		exit 1
	fi
}

check_env(){
	link_status=`[ -d /usr/local/mysql ] && echo '0' || echo '1'`
	if [ $link_status -eq 1 ];then
 		print_message "Warning" "软链已存在，将被替换为新版本的软链"
	fi

	[ ! -f $NEW_VERSION_PKG_PATH ] && echo "[Error] MySQL安装包不存在,当前传入路径为：$NEW_VERSION_PKG_PATH" && exit 1 || echo "[Note] 检测到需解压的新版压缩包: $NEW_VERSION_PKG_PATH"

	if [[ $MYSQL_NEW_VERSION > "8.0.15" ]];then
		print_message "Note" "版本>8.0.15,检测是否已安装mysql—shell "
		MYSQL_SHELL_STATUS=`rpm -qa|grep mysql-shell|wc -l`
		if [ $MYSQL_SHELL_STATUS -eq 1 ];then
        	print_message "Note" "mysql-shell 已安装"
        else
        	print_message "Error" "请先安装 mysql-shell \n可以执行如下命令，安装源：yum -y install https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm\n安装mysql-shell: yum install -y mysql-shell"
		fi 
	fi
}

up_set_innodb_fast_shutdown(){
	print_message "Note" "设置 innodb_fast_shutdown = 0 ，慢速关机"
	$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -Ne "set global innodb_fast_shutdown=0;"
}

up_check_xa(){
	print_message "Note" "检查 XA 事务..."
	XA_STATUS=`$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -Ne "XA RECOVER;"`
	if [[ $XA_STATUS > "0" ]];then
		print_message "Error" "存在未提交的XA事务，请登陆执行 XA RECOVER;后查看，确定后执行提交[XA COMMIT xid;]或回滚[XA ROLLBACK xid;]"	
		exit 1
	fi
}


up_start_mysql(){
	print_message "Note" "启动MySQL..."
	`$MYSQL_START_COMMAND`
}

up_stop_mysql(){
	print_message "Note" "关闭MySQL..."
	`$MYSQL_STOP_COMMAND`
}

up_restart_mysql(){
	print_message "Note" "重启MySQL..."
	`$MYSQL_RESTART_COMMAND`
}

up_stop_slave(){
  if [ $IS_SLAVE -eq 1 ];then
	print_message "Note" "关闭主从复制..."
	$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -Ne "stop slave;"
  fi
}

up_start_slave(){
  if [ $IS_SLAVE -eq 1 ];then
	print_message "Note" "启动主从复制..."
	$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -Ne "start slave;"
  fi
}

up_check_slave_status(){
  if [ $IS_SLAVE -eq 1 ];then
	print_message "Note" "主从复制状态如下："
	$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -e "show slave status\G"
  fi
}

up_backup_data(){
	if [ $IS_NEED_BACKUP = 1 ];then
		if [ -z $NEED_BACKUP_DIR ];then
		    print_message "Note" "进行备份中，目标路径:$DATA_DIR$DATA_TIME，请等待..."
			cp -rp $DATA_DIR $DATA_DIR$DATA_TIME
		elif [ -d $NEED_BACKUP_DIR ];then
			print_message "Note" "进行备份中，目标路径:$NEED_BACKUP_DIR/mysql_databack_$DATA_TIME，请等待..."
			cp -rp $DATA_DIR $NEED_BACKUP_DIR/mysql_databack_$DATA_TIME
		fi
	else
		print_message "Warning" "数据目录当前设置为无需进行备份..."
	fi
}

up_install_new_pkg(){
        print_message "Note" "安装包[$NEW_VERSION_PKG_PATH]解压中，请等待..."
	if [ -d $BASE_DIR/$MYSQL_UNCOMPRESS ];then
          print_message "Warning" "$BASE_DIR/$MYSQL_UNCOMPRESS 已存在..."
        else
          if [[ $MYSQL_NEW_VERSION > "8.0" ]];then
	    tar -xf $NEW_VERSION_PKG_PATH -C $BASE_DIR
	  else
	    tar -zxf $NEW_VERSION_PKG_PATH -C $BASE_DIR
          fi
	fi
#	## 创建软链
#  	print_message "Note" "检查配置软链..."
#  	if [ -L $MYSQL_LINK_DIR ];then
#    	is_link=`ls -l $MYSQL_LINK_DIR|grep -w $MYSQL_UNCOMPRESS|wc -l`
#    	if [[ $is_link -eq 0 ]];then
#      		print_message "Warning" "软链已存在,原软链为 : `ls -l $MYSQL_LINK_DIR`"
#      		unlink $MYSQL_LINK_DIR
#      		ln -s $BASE_DIR/$MYSQL_UNCOMPRESS $MYSQL_LINK_DIR
#      		print_message "Warning" "当前软链替换为 : `ls -l $MYSQL_LINK_DIR`"
#    	else
#      		print_message "Warning" "软链已存在"
#    	fi
#  	else
#    	ln -s $BASE_DIR/$MYSQL_UNCOMPRESS $MYSQL_LINK_DIR
#    	print_message "Note" "设置软链: `ls -l $MYSQL_LINK_DIR`"
#  	fi
}

up_config_link(){
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
}

up_exec_upgrade(){
	echo "[Note] 执行 mysql_upgrade 升级操作..."
	$MYSQL_LINK_DIR/bin/mysql_upgrade -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET > /tmp/mysql_upgrade.txt
	UPGRADE_STATUS=`cat /tmp/mysql_upgrade.txt|grep "Upgrade process completed successfully."|wc -l`
	if [ $UPGRADE_STATUS -eq 1 ];then
		print_message "Note" "执行inplace升级成功..."
	else
		print_message "Error" "执行inplace升级失败！"
	fi
}

up_load_fill_help_tables(){
	print_message "Note" "加载新的帮助表..."
	$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET mysql < $MYSQL_LINK_DIR/share/fill_help_tables.sql
	print_message "Note" "新的帮助表加载完成"
}

upgrade_mysql(){
	check_params
	check_env
	
	print_message "Note" "获取数据路径..."
	DATA_VARIABLES=`$MYSQL_LINK_DIR/bin/mysql -uroot -p"${ROOT_PASSWORD}" -S $ROOT_SOCKET -Ne "show variables like '%datadir%';"`
        MYSQL_DATA_DIR=`echo $DATA_VARIABLES|awk '{print $2}'`
        DATA_DIR=`echo ${MYSQL_DATA_DIR%/*}`
	print_message "Note" "当前数据路径地址为:$MYSQL_DATA_DIR"

	if [[ $MYSQL_NEW_VERSION > "8.0.15" ]];then
		print_message "Note" "使用check-for-server-upgrade工具进行升级前检查..."
		mysqlsh -- util check-for-server-upgrade --user=root --password="${ROOT_PASSWORD}" --socket=$ROOT_SOCKET --target-version=$MYSQL_NEW_VERSION --config-path=$NEW_MYCNF > /tmp/check_for_server_upgrade_$DATA_TIME.txt
		cat /tmp/check_for_server_upgrade_$DATA_TIME.txt
		CHECK_SERVER_UPGRADE_STATUS=`cat /tmp/check_for_server_upgrade_$DATA_TIME.txt|grep "No known compatibility errors or issues were found."|wc -l`
		rm -f /tmp/check_for_server_upgrade_$DATA_TIME.txt
		if [[ $CHECK_SERVER_UPGRADE_STATUS -eq 1 ]];then
			print_message "Note" "升级前检查通过，开始执行升级操作..."
			up_install_new_pkg
			up_stop_slave
			up_set_innodb_fast_shutdown
			up_check_xa
			#up_install_new_pkg
			up_stop_mysql
                        up_config_link
			up_backup_data
			up_start_mysql
			up_start_slave
			up_check_slave_status
			print_message "Note" "升级完成."
		elif [ $IS_UPGRADE_FORCE -eq 1 ];then
			print_message "Warning" "忽略告警，使用强制更新，开始执行升级操作..."
			up_install_new_pkg
			up_stop_slave
			up_set_innodb_fast_shutdown
			up_check_xa
			#up_install_new_pkg
			up_stop_mysql
                        up_config_link
			up_backup_data
			up_start_mysql
			up_start_slave
			up_check_slave_status
			print_message "Note" "升级完成."
		else
			print_message "Error" "升级前检查未通过，请检查！"
			exit 1
		fi
	elif [[ $MYSQL_NEW_VERSION > "5.6" ]] && [[ $MYSQL_NEW_VERSION < "8.0" ]];then
			print_message "Note" "升级前检查通过，开始执行升级操作..."
			up_install_new_pkg
                        up_stop_slave
			up_set_innodb_fast_shutdown
			up_check_xa
			#up_install_new_pkg
			up_stop_mysql
                        up_config_link
			up_backup_data
			up_start_mysql
			up_exec_upgrade
			up_load_fill_help_tables
			up_restart_mysql
			up_start_slave
			up_check_slave_status
			print_message "Note" "升级完成."
	fi
}

upgrade_mysql
