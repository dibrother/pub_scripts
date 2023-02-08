#!/bin/bash
set -e

BASE_DIR=$(cd $(dirname $0); pwd)
ERROR="Error"
WARNING="Warning"
INFO="Info"

print_message(){
  TAG=$1
  MSG=$2
  if [[ $TAG = $ERROR ]];then
    echo -e "$(date +'%F %T') [\033[31m$TAG\033[0m] $MSG"
  elif [[ $TAG = $WARNING ]];then
    echo -e "$(date +'%F %T') [\033[34m$TAG\033[0m] $MSG"
  else
    echo -e "$(date +'%F %T') [\033[32m$TAG\033[0m] $MSG"
  fi
}

err_message(){
    errmsg=$1
    print_message $ERROR "$1"
    exit 1
}

move_datadir(){
    if [ -a $DATA_DIR ];then
        mv $DATA_DIR $OLD_DATA_DIR
    fi
}

decompress(){
    mkdir -p $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME
    tar -zxf $BACKUP_FLIE_DIR/$BACKUP_FLIE_NAME -C $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME
    new_data=$(ls $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME)
}

check_diff_params(){
    source_innodb_data_file=$(cat $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME/$new_data/backup-my.cnf  |grep innodb_data_file_path|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    target_innodb_data_file=$(cat $CONFIG_FILE  |grep innodb_data_file_path|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    if [ "$source_innodb_data_file" = "" ];then
        source_innodb_data_file="ibdata1:12M:autoextend"
    fi
    if [ "$target_innodb_data_file" = "" ];then
        target_innodb_data_file="ibdata1:12M:autoextend"
    fi
    if [ "${source_innodb_data_file}" != "${target_innodb_data_file}" ];then
        print_message $ERROR "请将本地cnf文件中的innodb_data_file_path 值修改为${source_innodb_data_file},当前值为:$target_innodb_data_file"
        exit 1
    fi
    source_innodb_page_size=$(cat $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME/$new_data/backup-my.cnf  |grep innodb_page_size|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    target_innodb_page_size=$(cat $CONFIG_FILE |grep innodb_page_size|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    if [ "$target_innodb_page_size" = "" ];then
        target_innodb_page_size="16384"
    fi
    if [ "$source_innodb_page_size" = "" ];then
        source_innodb_page_size="16384"
    fi
    if [ "$source_innodb_page_size" != "$target_innodb_page_size" ];then
        print_message $ERROR "请将本地cnf文件中的innodb_page_size 值修改为${source_innodb_page_size},当前值为:$source_innodb_page_size"
        exit 1
    fi
    source_server_id=$(cat $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME/$new_data/backup-my.cnf  |grep server_id|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    target_server_id=$(cat $CONFIG_FILE |grep server_id|grep -v -E '^#'|awk -F "=" '{print $2}'|sed 's/[[:space:]]//g')
    if [ "$source_server_id" = "" ];then
        source_server_id="1"
    fi
    if [ "$target_server_id" = "" ];then
        target_server_id="1"
    fi
    if [ "$source_server_id" = "$target_server_id" ];then
        print_message $ERROR "server_id 不能与源库相同"
        exit 1
    fi
}

## 替换datadir
reset_datadir(){
    move_datadir
    mv $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME/$new_data $DATA_DIR
}

get_replica_version(){
    if [ $MYSQL_VERSION \> "8.0.22" ];then
        replica_statement="replica"
        source_statement="SOURCE"
        change_statement="CHANGE REPLICATION SOURCE TO"
    else
        replica_statement="slave"
        source_statement="MASTER"
        change_statement="CHANGE MASTER TO"
    fi
}

set_skip_replica_start(){
    skip_exist=$(cat $CONFIG_FILE | grep skip_${replica_statement}_start=1 | wc -l)
    if [ $skip_exist = "0" ];then
        echo -e "[mysqld]\nskip_${replica_statement}_start=1">>$CONFIG_FILE
    fi
}

reset_replica_all(){
    $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S$SOCKET_DIR -e"reset ${replica_statement} all;" >>$BASE_DIR/$ERROR_LOG 2>&1 || err_message "清除复制信息失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
}

del_skip_replica_start(){
    text1=$(tail -1 $CONFIG_FILE)
    if [ "$text1" = "skip_${replica_statement}_start=1" ];then
        sed -i '$d' $CONFIG_FILE
        sed -i '$d' $CONFIG_FILE
    fi
}

clone_recovery(){
    print_message $INFO "停止mysql..."
    $STOP_CMD
    print_message $INFO "解压备份文件..."
    decompress
    print_message $INFO "检查参数设置..."
    check_diff_params
    print_message $INFO "移动数据文件..."
    reset_datadir
    print_message $INFO "为数据目录授权..."
    chown -R mysql:mysql $DATA_DIR
    get_replica_version
    print_message $INFO "设置 --skip-replica-start=on..."
    set_skip_replica_start
    print_message $INFO "启动数据库..."
    $START_CMD
    print_message $INFO "reset replica all ..."
    reset_replica_all
    print_message $INFO "删除 --skip-replica-start=on..."
    del_skip_replica_start
}

find_binlog_files(){
    if $BINLOG_REMOTE;then
        binlog_info=$($MYSQL_DIR/bin/mysql -u$SOURCE_USERNAME -p$SOURCE_PASSWORD -h$SOURCE_HOSTIP -P$SOURCE_PORT -Ne"show master logs;" 2>> $BASE_DIR/$ERROR_LOG) || err_message "查找binlog文件失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    else
        binlog_info=$(ls $BINLOG_DIR)
    fi
    arr_binlogs=($binlog_info)
    binlogs=""
    for binlog in ${arr_binlogs[*]}
    do
    if [[ $binlog =~ ^($BINLOG_NAME).[0-9]+$ ]];then
        if [ !$STOP_FILE ];then
            if [ "$binlog" \> "$STOP_FILE" ] && [ "$RECOVERY_TYPE" = "pos" ];then
                break
            fi
        fi
        binlogs="$binlogs $binlog"
    fi
    done
    if [ "$binlogs" = "" ];then
        print_message $ERROR "未找到binlog文件:$BINLOG_NAME"
        exit 1
    fi
    print_message $INFO "当前binlog文件:$binlogs"
}

check_binlog(){
    master_status=$($MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -Ne"show master status;" 2>> $BASE_DIR/$ERROR_LOG) || err_message "获取GTID信息失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    arr_status=($master_status)
    exec_gtids=$(echo -e ${arr_status[2]})
    print_message $INFO "已执行的GTID集合:$exec_gtids"
    if $BINLOG_REMOTE;then
        first_binlog_gtid=$(mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD -v $binlogs 2>> $BASE_DIR/$ERROR_LOG | grep -E '^SET @@SESSION.GTID_NEXT= .+-.+' -m 1 | awk -F\' '{print $2}') || err_message "获取binlog起始GTID失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    else
        cd $BINLOG_DIR
        first_binlog_gtid=$(mysqlbinlog -v $binlogs 2>> $BASE_DIR/$ERROR_LOG| grep -E '^SET @@SESSION.GTID_NEXT= .+-.+' -m 1 | awk -F\' '{print $2}') || err_message "获取binlog起始GTID失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    fi 
    print_message $INFO "当前binlog文件的第一个GTID:$first_binlog_gtid"
    gtid_status=$($MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -Ne"select GTID_SUBSET('$first_binlog_gtid','$exec_gtids');" 2>> $BASE_DIR/$ERROR_LOG)  || err_message "比较GTID失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    if [[ $gtid_status = "1" ]];then
        print_message $INFO "即将开始增量恢复..."
    else
        print_message $ERROR "缺少binlog文件"
        exit 1
    fi
}

binlog_time_recovery(){
    if $BINLOG_REMOTE;then
        $MYSQL_DIR/bin/mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD $binlogs -v --exclude-gtids="$exec_gtids" --stop-datetime="$STOP_TIME" 2>> $BASE_DIR/$ERROR_LOG | $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} 2>> $BASE_DIR/$ERROR_LOG || err_message "增量恢复失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    else
        cd $BINLOG_DIR
        $MYSQL_DIR/bin/mysqlbinlog $binlogs -v --exclude-gtids="$exec_gtids" --stop-datetime="$STOP_TIME" 2>> $BASE_DIR/$ERROR_LOG | $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} 2>> $BASE_DIR/$ERROR_LOG || err_message "增量恢复失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    fi
}

binlog_pos_recovery(){
    if $BINLOG_REMOTE;then
        $MYSQL_DIR/bin/mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD $binlogs -v --exclude-gtids="$exec_gtids" --stop-position=$STOP_POS 2>> $BASE_DIR/$ERROR_LOG | $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} 2>> $BASE_DIR/$ERROR_LOG || err_message "增量恢复失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    else
        cd $BINLOG_DIR
        $MYSQL_DIR/bin/mysqlbinlog $binlogs -v --exclude-gtids="$exec_gtids" --stop-position=$STOP_POS 2>> $BASE_DIR/$ERROR_LOG | $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} 2>> $BASE_DIR/$ERROR_LOG || err_message "增量恢复失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    fi
}

get_pos(){
    if $BINLOG_REMOTE;then
        pos=$($MYSQL_DIR/bin/mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD $binlog -v --include-gtids="$STOP_GTID" 2>> $BASE_DIR/$ERROR_LOG | grep "$STOP_GTID" -B100 | grep -E '^(# at )[0-9]+$' | tail -1 | awk '{print $3}')  || err_message "获取stop pos 失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    else
        cd $BINLOG_DIR
        pos=$($MYSQL_DIR/bin/mysqlbinlog $BINLOG_DIR/$binlog -v --include-gtids="$STOP_GTID" | grep "$STOP_GTID" -B100 | grep -E '^(# at )[0-9]+$' | tail -1 | awk '{print $3}') || err_message "获取stop pos 失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    fi
}

set_gtid_pos(){
    arr_logs=($binlogs)
    binlogs=""
    for binlog in ${arr_logs[*]}
    do
        binlogs="$binlogs $binlog"
        get_pos
        if [ $pos ];then
            print_message $INFO "stop_binlog=$binlog,stop_pos=$pos"
            STOP_POS=$pos
            break
        fi
    done
}

find_stop_gtid(){
    BINLOG_REMOTE=true
    find_binlog_files
    check_binlog
    rec_until="BEFORE"
    gtid=$($MYSQL_DIR/bin/mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD $binlogs -v --start-datetime="$STOP_TIME" 2>> $BASE_DIR/$ERROR_LOG | grep -E '^SET @@SESSION.GTID_NEXT= .+-.+' -m 1 | awk -F\' '{print $2}') || err_message "获取STOP GTID 失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    if [ !$gtid ];then
        rec_until="AFTER"
        gtid=$($MYSQL_DIR/bin/mysqlbinlog --read-from-remote-server --host=$SOURCE_HOSTIP --port=$SOURCE_PORT --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD $binlogs -v --exclude-gtids="$exec_gtids" --stop-datetime="$STOP_TIME" 2>> $BASE_DIR/$ERROR_LOG | grep -E '^SET @@SESSION.GTID_NEXT= .+-.+' | tail -1 | awk -F\' '{print $2}') || err_message "获取STOP GTID 失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
    fi
    if [ $gtid ];then
        print_message $INFO "stop_gtid=$gtid"
        STOP_GTID=$gtid
    else
        print_message $ERROR "查找GTID失败"
        exit 1
    fi
}

replica_pos_recovery(){
    $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -e"$change_statement ${source_statement}_HOST = '$SOURCE_HOSTIP',${source_statement}_PORT = $SOURCE_PORT,${source_statement}_USER = '$SOURCE_USERNAME',${source_statement}_PASSWORD = '${SOURCE_PASSWORD}',${source_statement}_AUTO_POSITION = 1;START $replica_statement UNTIL ${source_statement}_LOG_FILE = '$STOP_FILE', MASTER_LOG_POS = $STOP_POS;" 2>> $BASE_DIR/$ERROR_LOG || err_message "复制信息设置失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
}

replica_gtid_recovery(){
    $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -e"$change_statement ${source_statement}_HOST = '$SOURCE_HOSTIP',${source_statement}_PORT = $SOURCE_PORT,${source_statement}_USER = '$SOURCE_USERNAME',${source_statement}_PASSWORD = '${SOURCE_PASSWORD}',${source_statement}_AUTO_POSITION = 1;START $replica_statement UNTIL SQL_${rec_until}_GTIDS='$STOP_GTID';" 2>> $BASE_DIR/$ERROR_LOG || err_message "复制信息设置失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
}

wait_replica_complete(){
    while [ true ]; do
        replica_status=$($MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -e"show $replica_statement status\G" 2>> $BASE_DIR/$ERROR_LOG) || err_message "查询增量信息失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
        Replica_IO_Running=$(echo "$replica_status" | grep -i "${replica_statement}_IO_Running" | awk -F: '{print $2}' | sed 's/[[:space:]]//g')
        Replica_SQL_Running=$(echo "$replica_status" | grep -i "${replica_statement}_SQL_Running" | grep -v "State" | awk -F: '{print $2}' | sed 's/[[:space:]]//g')
        err=$(echo "$replica_status" | grep -i "error" | awk -F: '{print $2}')
        err=$(echo $err | sed 's/[[:space:]]//g')
        Executed_Gtid_Set=$(echo "$replica_status" | grep -i 'Executed_Gtid_Set' -A1000 | grep 'Auto_Position' -B1000 | grep -v 'Auto_Position')
        print_message $INFO "当前进度:$Executed_Gtid_Set"
        if [ $err  ];then
            print_message $ERROR "复制出错,在mysql中执行'show ${replica_statement} status\G'查看详细信息"
            exit 1
        elif [ $Replica_IO_Running = "Yes" ] && [ $Replica_SQL_Running = "No" ];then
            print_message $INFO "复制完成"
            break
        fi
        sleep 5s
    done
}

reset_replica(){
    $MYSQL_DIR/bin/mysql -u$USERNAME -p$PASSWORD -S ${SOCKET_DIR} -e"stop $replica_statement;reset $replica_statement all;" 2>> $BASE_DIR/$ERROR_LOG || err_message "清除复制信息失败，可查看$BASE_DIR/$ERROR_LOG 获取详细信息"
}

print_usage(){
    printf "Usage: bash 
        clone_recover.sh full     仅全量恢复（配置文件full_rec.conf）
        clone_recover.sh time     增量恢复到某个时间点（配置文件time_rec.conf）
        clone_recover.sh pos      增量恢复到某个POS点（配置文件pos_rec.conf）
        clone_recover.sh gtid     增量恢复到某个GTID（配置文件gtid_rec.conf）
"
}

if [ "$1" = "full" ];then
    source $BASE_DIR/full_rec.conf
elif [ "$1" = "time" ];then
    source $BASE_DIR/time_rec.conf
elif [ "$1" = "pos" ];then
    source $BASE_DIR/pos_rec.conf
elif [ "$1" = "gtid" ];then
    source $BASE_DIR/gtid_rec.conf
else
    print_usage
    exit 1
fi

OLD_DATA_DIR=${DATA_DIR}_$(date "+%Y%m%d%H%M%S")
TMP_BACKUP_NAME="backup_$(date "+%Y%m%d%H%M%S")"
RECOVERY_TYPE=$1

clone_recovery
print_message $INFO "全量恢复完成"

if [ "$RECOVERY_TYPE" != "full" ];then
    print_message $INFO "增量恢复..."
    if [ "$INCRE_TYPE" = "binlog" ];then
        print_message $INFO "获取binlog信息..."
        find_binlog_files
        print_message $INFO "检查binlog..."
        check_binlog
        if [ "$RECOVERY_TYPE" = "time" ];then
            print_message $INFO "binlog_time_recovery..."
            binlog_time_recovery
        elif [ "$RECOVERY_TYPE" = "pos" ];then
            print_message $INFO "binlog_pos_recovery..."
            binlog_pos_recovery
        elif [ "$RECOVERY_TYPE" = "gtid" ];then
            print_message $INFO "binlog_gtid_recovery..."
            print_message $INFO "查找pos点..."
            set_gtid_pos
            print_message $INFO "binlog_pos_recovery..."
            binlog_pos_recovery
        fi
    elif [ "$INCRE_TYPE" = "replica" ];then
        if [ "$RECOVERY_TYPE" = "time" ];then
            print_message $INFO "replica_time_recovery..."
            print_message $INFO "查找STOP_GTID..."
            find_stop_gtid
            print_message $INFO "replica_gtid_recovery..."
            replica_gtid_recovery
        elif [ "$RECOVERY_TYPE" = "pos" ];then
            print_message $INFO "replica_pos_recovery..."
            replica_pos_recovery
        elif [ "$RECOVERY_TYPE" = "gtid" ];then
            print_message $INFO "replica_gtid_recovery..."
            replica_gtid_recovery
        fi
        print_message $INFO "等待复制完成..."
        wait_replica_complete
        print_message $INFO "清除复制信息..."
        reset_replica
    fi
fi

if [[ $DEL_OLD_DATA = 1 ]]&& [[ ${OLD_DATA_DIR} =~ "_" ]];then
    print_message $INFO "删除原数据目录..."
    rm -rf $OLD_DATA_DIR
fi
print_message $INFO "删除已使用的备份文件..."
if [[ ${TMP_BACKUP_NAME} =~ "backup" ]];then
    rm -rf $BACKUP_FLIE_DIR/$TMP_BACKUP_NAME
fi

if [[ $DEL_BACKUP = 1 ]];then
    rm -f $BACKUP_FLIE_DIR/$BACKUP_FLIE_NAME
fi
print_message $INFO "恢复完成"
