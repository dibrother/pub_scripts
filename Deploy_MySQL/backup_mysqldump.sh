#!/bin/bash
set -e

###### 需要创建用户与授权 #####
# create user 'bak_user'@'127.0.0.1' identified by 'Yangq#123';
# grant reload,lock tables,replication client,create tablespace,process,event,trigger,select,show view on *.* to 'bak_user'@'%';

echo "begin..."

# 参数
BAKDATE=`date "+%Y_%m_%d_%H%M%S"`
BIN_DIR="/usr/local/mysql/bin"
BAK_DIR="/data/backup"
SAVE_DAYS=7

# Database info
DB_USER="bak_user"
DB_PASS="Yangq#123"
DB_HOST="127.0.0.1"
DB_PORT="3306"

# cd到备份路径
cd $BAK_DIR

# 删除30天前的备份数据
#find /data/backup/ -type d -mtime +30 -exec rm -rf {} \;
if [ -d ${BAK_DIR} ];then
  find ${BAK_DIR} -type f -mtime +${SAVE_DAYS} -exec rm -rf {} \;
fi



# 备份全库
echo "$BIN_DIR/mysqldump --single-transaction --master-data=2 -u$DB_USER -p$DB_PASS -h$DB_HOST -P$DB_PORT -A -R -E > $BAK_DIR/fullback_$BAKDATE.sql"

$BIN_DIR/mysqldump --single-transaction --master-data=2 -u$DB_USER -p$DB_PASS -h$DB_HOST -P$DB_PORT -A -R -E > $BAK_DIR/fullback_$BAKDATE.sql
# $BIN_DIR/mysqldump --single-transaction --master-data=2 -u$DB_USER -p$DB_PASS -h$DB_HOST -A -R -E|gzip > $BAK_DIR/fullback_$BAKDATE.gz

echo "backup done"
