## 说明
> 脚本基于 CentOS 7.9 开发，其余系统未经过完全测试

- 支持 5.7/8.0
- 支持单机部署
- 支持主从部署
- 支持高可用部署
   - 3台  orch模式
   - 2台/3台  replication-manager 模式
- 支持钉钉告警（加签方式）
- 支持 mysqldump 方式备份
- 支持xtrabackup备份
- 支持8.0 clone 方式备份
- 支持全量恢复
- 支持基于时间点恢复
- 支持基于binlog恢复
- 支持一键升级MySQL小版本
- 支持一键将恢复备份结果或dead旧主加回集群
## 部署
```shell
[root@test151 installMysql]# ./deploy_mysql.sh 
Usage: bash 
    deploy_mysql.sh single                  部署单机
    deploy_mysql.sh master                  部署主节点,会安装半同步插件,且开启主节点相关参数
    deploy_mysql.sh slave                   部署从节点,会安装半同步插件,且开启从节点相关参数
    deploy_mysql.sh as-slave                作为从库进行部署,需要主节点已部署,会作为从节点部署且建立好主从关系
    deploy_mysql.sh change-master           与配置文件中的主实例建立主从关系,仅做了change master操作    
    deploy_mysql.sh ha2master [orch/replm]  高可用主节点部署,同时部署 orchestrator/replication-manager高可用插件
    deploy_mysql.sh ha2slave  [orch/replm]  高可用从节点部署,同时部署 orchestrator/replication-manager 高可用插件
    deploy_mysql.sh cleanup [3306]          传入端口号,清空部署的相关信息
```
### 修改配置文件
vim ./config/user.conf
```shell
# basic 基础配置
MYSQL_PKG=mysql-8.0.30-linux-glibc2.12-x86_64.tar.xz
#MYSQL_PKG=mysql-5.7.40-linux-glibc2.12-x86_64.tar.gz
# MySQL数据目录，注意对应挂载磁盘路径
MYSQL_DATA_DIR=/data
# MySQL 端口
MYSQL_PORT=3311
# 默认获取服务器物理内存，可自定义
MEMORY_ALLLOW_GB=`free -g|grep Mem|awk '{print $2}'`
# 本机IP，需要根据当前服务器IP更改
IPADDR=192.168.60.151
# 密码不能使用双引号包裹
INIT_PASSWORD='123456'

########## HA模式或启用复制时候需要配置参数值 ############
# 主节点地址
SOURCE_IPADDR=192.168.60.151
# 需创建的复制用户名称密码
REPL_USER="repl"
REPL_PASSWORD='i@jod!drRBia0fja'
IP_SEGMENT='%'

########## 部署高可用(HA)模式时候需要设置的参数 ############
# VIP，必须要有VIP
VIP="192.168.60.111"
# 网卡名称，可使用 [ip -4 a] 查看
NET_WORK_CARD_NAME='ens33'
# 高可用组件使用的MySQL用户，会在主库创建
HA_USER='ha_monitor'
HA_PASSWORD='WWXXSiFK6X^hwkR4dQ'
# 高可用组件web界面登陆用户名密码
HA_HTTP_USER='admin'
HA_HTTP_PASSWORD='Yq@12#456'
# Orch高可用组件的web端口,默认3000,replication-manager组件不根据此参数更改，默认使用10001/10005
HA_PORT=3000
# 逗号分割，高可用组件自身高可用，若设置为空，则仅单机部署，组件自身没有高可用，若orch组件挂掉则无法支持数据库切换
HA_NODES='192.168.60.151,192.168.60.152,192.168.60.153'
# ssh 端口,默认使用免密使用的是 root 用户,而端口一般默认都是 22 ,当前示例是由于端口已被修改为 60022
SSH_PORT=6122

########################  发生切换时钉钉告警配置  ##########################
# msg_title ：信息标题
# dingding_url ：钉钉webhook地址
# 钉钉告警状态 0:关闭 1:开启
# 钉钉根据关键字告警,需要配置 "通知","异常"为关键字
#DINGDING_ALARM_STATUS=1
#MSG_TITLE="数据库切换告警"
#DINGDING_URL=https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

########################  dingding通知配置[可选修改]  ##########################
# 钉钉开关
DINGDING_SWITCH=0
MSG_TITLE="钉钉消息通知"
WEBHOOK_URL='https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
SECRET='SECxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
# 支持 text/markdown
SEND_TYPE="markdown"
# IS_AT_ALL 中设置任何值代表执行 true ,默认为false
IS_AT_ALL=""
# 设置电话号码会@那个人,这个设置值的话 -at_all 参数不能配置"
AT_MOBILES=""
```
### 单节点部署
```shell
deploy_mysql.sh single
```
### 主从部署
```shell
# 单独部署主节点
deploy_mysql.sh master

# 单独部署从节点（暂不作为从库加入集群）
deploy_mysql.sh slave
```
### 高可用部署
> - MySQL服务器均需要配置免密
> - 需要有一个VIP地址
> - ORCH 模式需要 3台，replication-manager模式 >= 2台
> - ORCH 模式中间件自带raft高可用，replication-manager模式中间件单节点且安装在最后一台从服务器上

```shell
# ORCH 组件模式
## 主节点
deploy_mysql.sh ha2master orch
## 从节点
deploy_mysql.sh ha2slave orch

# replication-manager 模式
## 主节点
deploy_mysql.sh ha2master replm
## 从节点
deploy_mysql.sh ha2slave replm
```
## 备份
### mysqldump-全备
> 主库创建备份用户

```shell
create user 'bak_user'@'127.0.0.1' identified by 'Yangq#123';
grant reload,lock tables,replication client,create tablespace,process,event,trigger,select,show view on *.* to 'bak_user'@'127.0.0.1';
```
> 修改backup_mysqldump.sh中的用户名端口信息，执行备份

```shell
./backup_mysqldump.sh
```
### xtrabackup-全备
> 下载安装 xtrabackup  [https://www.percona.com/software/mysql-database/percona-xtrabackup](https://www.percona.com/software/mysql-database/percona-xtrabackup)

```shell
# 例如安装 8.0.30 版本
wget https://downloads.percona.com/downloads/Percona-XtraBackup-8.0/Percona-XtraBackup-8.0.30-23/binary/redhat/7/x86_64/percona-xtrabackup-80-8.0.30-23.1.el7.x86_64.rpm
yum localinstall percona-xtrabackup-80-8.0.30-23.1.el7.x86_64.rpm -y
```
> 主库创建备份用户

```shell
CREATE USER 'databak'@'localhost' IDENTIFIED BY '123456';
GRANT BACKUP_ADMIN, PROCESS, RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'databak'@'localhost';
GRANT SELECT ON performance_schema.log_status TO 'databak'@'localhost';
GRANT SELECT ON performance_schema.keyring_component_status TO'databak'@'localhost';
GRANT SELECT ON performance_schema.replication_group_members TO databak@'localhost';
```
> 修改配置文件
> vim config/backup_xtrabackup.conf

- 修改备份地址与备份保留时长
- 修改对应用户名密码等信息
- 使用远程备份
   - 远程端已创建对应的存储目录
   - 备份机访问远程端机器免密
- 钉钉自定义开启
> 备份

```shell
# 本地备份
[root@test153 installMysql]# ./backup_xtrabackup.sh backup
2023-02-07 11:14:29 [Note] 进行备份前预检查
2023-02-07 11:14:29 [Note] 预检查完成
2023-02-07 11:14:29 [Note] 开始清理历史备份
2023-02-07 11:14:29 [Note] 清理历史备份清理完成
2023-02-07 11:14:29 [Note] 开始进行本地备份
2023-02-07 11:14:34 [Note] 备份[xtra_full_20230207111429.xb]成功
2023-02-07 11:14:34 [Note] 本地备份完成

# 远程备份，远程备份采用流式备份
[root@test153 installMysql]# ./backup_xtrabackup.sh backup
2023-02-07 11:14:55 [Note] 进行备份前预检查
2023-02-07 11:14:56 [Note] 预检查完成
2023-02-07 11:14:56 [Note] 开始清理历史备份
2023-02-07 11:14:56 [Warning] 当前远程备份文件为空,无需清理.
2023-02-07 11:14:56 [Note] 清理历史备份清理完成
2023-02-07 11:14:56 [Note] 开始进行远程备份
2023-02-07 11:14:59 [Note] 备份[xtra_full_20230207111455.xb]成功
2023-02-07 11:14:59 [Note] 远程备份完成
```
### clone 备份

- 需要安装 clone 插件
- 需要版本完全一致
- 远程备份的话需要远程端同样安装一致的MySQL
- 本地备份需要注意磁盘 double 空间
> 创建clone用户

```shell
create user 'clone_user'@'%' identified by '123456';
grant BACKUP_ADMIN,CLONE_ADMIN on *.* to 'clone_user'@'%';
grant select on performance_schema.global_variables to 'clone_user'@'%';
grant select on performance_schema.clone_progress to 'clone_user'@'%';
# 远程备份需要授权
grant SYSTEM_VARIABLES_ADMIN on *.* to 'clone_user'@'%';
```
> 备份

```shell
# 本地备份
[root@test153 installMysql]# ./backup_clone.sh local
2023-02-07 15:04:03 [Note] 进行备份前预检查
2023-02-07 15:04:03 [Note] 开始本地clone备份...
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 15:04:03 [Note] 备份my.cnf信息
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 15:04:03 [Note] 进行备份压缩...
2023-02-07 15:04:07 [Note] 删除已压缩文件
2023-02-07 15:04:07 [Note] 文件压缩完成
2023-02-07 15:04:07 [Note] [clone_full_20230207150403]clone备份成功
2023-02-07 15:04:07 [Note] 发送钉钉通知...
2023-02-07 15:04:07 [Note] 钉钉消息发送成功
2023-02-07 15:04:07 [Note] 钉钉通知完成...
2023-02-07 15:04:07 [Note] 开始清理备份...
2023-02-07 15:04:07 [Note] 清理完成,清理的是：

# 远程备份
[root@test153 installMysql]# ./backup_clone.sh remote
2023-02-07 15:33:30 [Note] 进行备份前预检查
2023-02-07 15:33:30 [Note] 开始远程clone备份,源地址：192.168.60.152:3311...
mysql: [Warning] Using a password on the command line interface can be insecure.
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 15:33:31 [Note] 备份my.cnf信息
mysql: [Warning] Using a password on the command line interface can be insecure.
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 15:33:32 [Note] 进行备份压缩...
2023-02-07 15:33:35 [Note] 删除已压缩文件
2023-02-07 15:33:35 [Note] 文件压缩完成
2023-02-07 15:33:35 [Note] [clone_full_20230207153330]远程clone备份成功
2023-02-07 15:33:35 [Note] 发送钉钉通知...
2023-02-07 15:33:35 [Note] 钉钉消息发送成功
2023-02-07 15:33:35 [Note] 钉钉通知完成...
2023-02-07 15:33:35 [Note] 开始清理备份...
2023-02-07 15:33:35 [Note] 清理完成,清理的是：
```
## 恢复
> 注意：恢复脚本会对原数据目录进行 move，请注意磁盘空间是否足够，若不够请先手动清楚数据目录数据

### mysqldump-恢复
```shell
mysql -uxxx -p -P3311 -hxxx.xxx.xxx.xx < xxx.sql
```
### xtrabackup-恢复
#### 全量恢复-full

- 首先修改 full_rec.conf
- 然后执行恢复
```shell
# full 恢复
[root@test153 xtra_recovery]# ./xtra_recover.sh full
2023-02-07 15:42:38 [Info] 安装解压工具qpress...
2023-02-07 15:42:38 [Warning] qpress工具已存在
2023-02-07 15:42:38 [Info] 解包xbstream文件...
2023-02-07 15:42:39 [Info] 使用qpress解压...
2023-02-07 15:42:40 [Info] 检查参数设置是否正确...
2023-02-07 15:42:40 [Info] prepare...
2023-02-07 15:42:43 [Info] 停止mysql...
2023-02-07 15:42:47 [Info] 移动原数据文件...
2023-02-07 15:42:47 [Info] 恢复中...
2023-02-07 15:42:47 [Info] 为数据目录授权...
2023-02-07 15:42:47 [Info] 设置 --skip-replica-start=on...
2023-02-07 15:42:47 [Info] 启动数据库...
2023-02-07 15:42:58 [Info] reset replica all ...
2023-02-07 15:42:58 [Info] 删除 --skip-replica-start=on...
2023-02-07 15:42:58 [Info] 全量恢复完成
2023-02-07 15:42:58 [Info] 删除原数据目录...
2023-02-07 15:42:59 [Info] 删除已使用的备份文件...
2023-02-07 15:42:59 [Info] 恢复完成
```
#### 基于 gtid 恢复(恢复到某GTID)

- 修改  gtid_rec.conf
- 支持 远程拉取binlog或使用本地上传的binlog恢复
- 支持作为从库方式进行恢复
- 恢复到指定的GTID前(不含指定的GTID)
```shell
# 根据远程拉取binlog进行恢复 （INCRE_TYPE="binlog"）
[root@test153 xtra_recovery]# ./xtra_recover.sh gtid
2023-02-07 15:57:06 [Info] 安装解压工具qpress...
2023-02-07 15:57:06 [Warning] qpress工具已存在
2023-02-07 15:57:06 [Info] 解包xbstream文件...
2023-02-07 15:57:06 [Info] 使用qpress解压...
2023-02-07 15:57:07 [Info] 检查参数设置是否正确...
2023-02-07 15:57:07 [Info] prepare...
2023-02-07 15:57:10 [Info] 停止mysql...
2023-02-07 15:57:13 [Info] 移动原数据文件...
2023-02-07 15:57:13 [Info] 恢复中...
2023-02-07 15:57:13 [Info] 为数据目录授权...
2023-02-07 15:57:13 [Info] 设置 --skip-replica-start=on...
2023-02-07 15:57:13 [Info] 启动数据库...
2023-02-07 15:57:18 [Info] reset replica all ...
2023-02-07 15:57:18 [Info] 删除 --skip-replica-start=on...
2023-02-07 15:57:18 [Info] 全量恢复完成
2023-02-07 15:57:18 [Info] 增量恢复...
2023-02-07 15:57:18 [Info] 获取binlog信息...
2023-02-07 15:57:18 [Info] 当前binlog文件: mysql-bin.000001 mysql-bin.000002
2023-02-07 15:57:18 [Info] 检查binlog...
2023-02-07 15:57:18 [Info] 已执行的GTID集合:0deaede6-a5ca-11ed-8c15-000c29957715:1-19
2023-02-07 15:57:18 [Info] 当前binlog文件的第一个GTID:0deaede6-a5ca-11ed-8c15-000c29957715:1
2023-02-07 15:57:18 [Info] 即将开始增量恢复...
2023-02-07 15:57:18 [Info] binlog_gtid_recovery...
2023-02-07 15:57:18 [Info] 查找pos点...
2023-02-07 15:57:18 [Info] stop_binlog=mysql-bin.000002,stop_pos=7539
2023-02-07 15:57:18 [Info] binlog_pos_recovery...
2023-02-07 15:57:18 [Info] 删除原数据目录...
2023-02-07 15:57:19 [Info] 删除已使用的备份文件...
2023-02-07 15:57:19 [Info] 恢复完成


# 伪装成从库进行恢复  (INCRE_TYPE="replica")
[root@test153 xtra_recovery]# ./xtra_recover.sh gtid
2023-02-07 16:09:27 [Info] 安装解压工具qpress...
2023-02-07 16:09:27 [Warning] qpress工具已存在
2023-02-07 16:09:27 [Info] 解包xbstream文件...
2023-02-07 16:09:27 [Info] 使用qpress解压...
2023-02-07 16:09:28 [Info] 检查参数设置是否正确...
2023-02-07 16:09:29 [Info] prepare...
2023-02-07 16:09:31 [Info] 停止mysql...
2023-02-07 16:09:34 [Info] 移动原数据文件...
2023-02-07 16:09:34 [Info] 恢复中...
2023-02-07 16:09:34 [Info] 为数据目录授权...
2023-02-07 16:09:34 [Info] 设置 --skip-replica-start=on...
2023-02-07 16:09:34 [Info] 启动数据库...
2023-02-07 16:09:39 [Info] reset replica all ...
2023-02-07 16:09:39 [Info] 删除 --skip-replica-start=on...
2023-02-07 16:09:39 [Info] 全量恢复完成
2023-02-07 16:09:39 [Info] 增量恢复...
2023-02-07 16:09:39 [Info] replica_gtid_recovery...
2023-02-07 16:09:39 [Info] 等待复制完成...
2023-02-07 16:09:39 [Info] 当前进度:            Executed_Gtid_Set: 0deaede6-a5ca-11ed-8c15-000c29957715:1-19
2023-02-07 16:09:44 [Info] 当前进度:            Executed_Gtid_Set: 0deaede6-a5ca-11ed-8c15-000c29957715:1-28
2023-02-07 16:09:44 [Info] 复制完成
2023-02-07 16:09:44 [Info] 清除复制信息...
2023-02-07 16:09:45 [Info] 删除原数据目录...
2023-02-07 16:09:45 [Info] 删除已使用的备份文件...
2023-02-07 16:09:45 [Info] 恢复完成
```
#### 基于时间点的恢复

- 编辑 time_rec.conf
```shell
[root@test153 xtra_recovery]# ./xtra_recover.sh time
2023-02-07 16:17:25 [Info] 安装解压工具qpress...
2023-02-07 16:17:25 [Warning] qpress工具已存在
2023-02-07 16:17:25 [Info] 解包xbstream文件...
2023-02-07 16:17:25 [Info] 使用qpress解压...
2023-02-07 16:17:26 [Info] 检查参数设置是否正确...
2023-02-07 16:17:26 [Info] prepare...
2023-02-07 16:17:29 [Info] 停止mysql...
2023-02-07 16:17:32 [Info] 移动原数据文件...
2023-02-07 16:17:32 [Info] 恢复中...
2023-02-07 16:17:33 [Info] 为数据目录授权...
2023-02-07 16:17:33 [Info] 设置 --skip-replica-start=on...
2023-02-07 16:17:33 [Info] 启动数据库...
2023-02-07 16:17:37 [Info] reset replica all ...
2023-02-07 16:17:37 [Info] 删除 --skip-replica-start=on...
2023-02-07 16:17:37 [Info] 全量恢复完成
2023-02-07 16:17:37 [Info] 增量恢复...
2023-02-07 16:17:37 [Info] replica_time_recovery...
2023-02-07 16:17:37 [Info] 查找STOP_GTID...
2023-02-07 16:17:37 [Info] 当前binlog文件: mysql-bin.000001 mysql-bin.000002
2023-02-07 16:17:37 [Info] 已执行的GTID集合:0deaede6-a5ca-11ed-8c15-000c29957715:1-19
2023-02-07 16:17:38 [Info] 当前binlog文件的第一个GTID:0deaede6-a5ca-11ed-8c15-000c29957715:1
2023-02-07 16:17:38 [Info] 即将开始增量恢复...
2023-02-07 16:17:38 [Info] stop_gtid=0deaede6-a5ca-11ed-8c15-000c29957715:29
2023-02-07 16:17:38 [Info] replica_gtid_recovery...
2023-02-07 16:17:38 [Info] 等待复制完成...
2023-02-07 16:17:38 [Info] 当前进度:            Executed_Gtid_Set: 0deaede6-a5ca-11ed-8c15-000c29957715:1-19
2023-02-07 16:17:43 [Info] 当前进度:            Executed_Gtid_Set: 0deaede6-a5ca-11ed-8c15-000c29957715:1-28
2023-02-07 16:17:43 [Info] 复制完成
2023-02-07 16:17:43 [Info] 清除复制信息...
2023-02-07 16:17:43 [Info] 删除原数据目录...
2023-02-07 16:17:43 [Info] 删除已使用的备份文件...
2023-02-07 16:17:43 [Info] 恢复完成
```
### clone 恢复
同上，编辑 full_rec.conf 等文件
```shell
# full 恢复
[root@test153 clone_recovery]# ./clone_recover.sh full
2023-02-07 16:30:32 [Info] 停止mysql...
2023-02-07 16:30:36 [Info] 解压备份文件...
2023-02-07 16:30:37 [Info] 检查参数设置...
2023-02-07 16:30:37 [Info] 移动数据文件...
2023-02-07 16:30:37 [Info] 为数据目录授权...
2023-02-07 16:30:37 [Info] 设置 --skip-replica-start=on...
2023-02-07 16:30:37 [Info] 启动数据库...
2023-02-07 16:30:43 [Info] reset replica all ...
2023-02-07 16:30:43 [Info] 删除 --skip-replica-start=on...
2023-02-07 16:30:43 [Info] 全量恢复完成
2023-02-07 16:30:43 [Info] 删除原数据目录...
2023-02-07 16:30:43 [Info] 删除已使用的备份文件...
2023-02-07 16:30:43 [Info] 恢复完成
```
## 作为从库加入
```shell
[root@test153 installMysql]# ./rejoin_to_slave.sh 192.168.60.151
2023-02-07 16:31:11 [Note] MySQL已启动...
2023-02-07 16:31:11 [Note] 新旧GTID确认比对...
mysql: [Warning] Using a password on the command line interface can be insecure.
mysql: [Warning] Using a password on the command line interface can be insecure.
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 16:31:11 [Note] 配置主从关系，主为：192.168.60.151
2023-02-07 16:31:11 [Note] 设置从库相关参数(rpl_semi_sync_master_enabled=0,rpl_semi_sync_slave_enabled=1)
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 16:31:11 [Note] 当前从库rpl_semi_sync_master_enabled,pl_semi_sync_slave_enabled 已设置
2023-02-07 16:31:11 [Note] 建立主从关系，目标主库地址为：192.168.60.151
mysql: [Warning] Using a password on the command line interface can be insecure.
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 16:31:11 [Note] 主从关系建立成功
2023-02-07 16:31:11 [Note] 将当前从库设置为只读(read_only=1,super_read_only=1)
mysql: [Warning] Using a password on the command line interface can be insecure.
2023-02-07 16:31:11 [Note] 当前从库已设置为只读
```

