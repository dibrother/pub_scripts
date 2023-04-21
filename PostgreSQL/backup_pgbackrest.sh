#!/bin/bash
current_dir=$(cd $(dirname $0); pwd)

pgbackrest=/usr/bin/pgbackrest
stanza=pro
who=$(whoami)
# 备份时长间隔
task_interval="55 02 * * *"



# 全备
function backup_full(){
  if [ $who = "postgres" ];then
    ${pgbackrest} --stanza=${stanza} --log-level-console=info --type=full backup
    backup_status $?
  else
    su - postgres -c "${pgbackrest} --stanza=${stanza} --log-level-console=info --type=full backup"
    backup_status $?
  fi
}

function backup_incr(){
  if [ $who = "postgres" ];then
      ${pgbackrest} --stanza=${stanza} --log-level-console=info --type=incr backup
      backup_status $?
  else
      su - postgres -c "${pgbackrest} --stanza=${stanza} --log-level-console=info --type=incr backup"
      backup_status $?
  fi
}

# 检查备份状态
function backup_status(){
  bk_status=$1
  # 输出备份结果
  if [ $bk_status -eq 0 ]; then
    echo "Backup successful"
  else
    echo "Backup failed!"
  fi
}

function backup_add_crontab(){
    cat >> /etc/crontab << EOF
${task_interval} root /bin/bash ${current_dir}/backup_pgbackrest.sh full > /dev/null 2>&1
EOF
}

# 使用说明
usage () {
        cat <<EOF
Usage: $0 [OPTIONS]
  full                      执行全备
  incr                      执行增备
  add_crontab               添加备份定时任务，默认备份时间为每日[02:55]
EOF
exit 1
}

# main 入口
command="${1}"
case "${command}" in
    "full" )
	    backup_full
    ;;
    "incr" )
	    backup_incr
    ;;
    "add_crontab" )
	    backup_add_crontab
    ;;
    * )
        usage
    ;;
esac