> 文档：[https://pgbackrest.org/user-guide-rhel.html#build](https://pgbackrest.org/user-guide-rhel.html#build)
> 下载：[https://github.com/pgbackrest/pgbackrest/tags](https://github.com/pgbackrest/pgbackrest/tags)

## 安装
> 可以其他机器编译生成后拷贝到对应服务器使用
> 编译前yum安装个postgresql下

### 下载解压
```shell
wget https://github.com/pgbackrest/pgbackrest/archive/refs/tags/release/2.45.tar.gz
tar zxf 2.45.tar.gz -C /opt
```
### 安装依赖包
```shell
yum install -y centos-release-scl
yum install -y make gcc postgresql12-devel openssl-devel libxml2 libxml2-devel openssl libyaml-devel  bzip2 bzip2-devel
```
### 编译安装
```shell
chown -R postgres:postgres /opt/pgbackrest-release-2.45
su - postgres
cd /opt/pgbackrest-release-2.45/src
./configure && make
# 确认下是否正常
./pgbackrest
cp /opt/pgbackrest-release-2.45/src/pgbackrest /usr/bin/
```
## 配置
### 创建目录
```shell
# 创建pgbackrest相关目录
mkdir -p -m 770 /var/log/pgbackrest
mkdir -p /etc/pgbackrest
touch /etc/pgbackrest/pgbackrest.conf
chmod 640 /etc/pgbackrest/pgbackrest.conf
chown postgres:postgres /var/log/pgbackrest
chown postgres:postgres /etc/pgbackrest/pgbackrest.conf

# 备份存放路径
mkdir /app/pgsql/backup
chmod 750 /app/pgsql/backup/
chown postgres:postgres /app/pgsql/backup/
```
### 配置postgresql
> vim /app/pgsql/data/postgresql.conf

```shell
# 当前已开启归档，修改如下
archive_command = 'pgbackrest --stanza=demo archive-push %p'
# 重启PG
systemctl restart postgresql-12
```
### 配置pgbackrest
> vim /etc/pgbackrest/pgbackrest.conf

```shell
[demo]
pg1-path=/app/pgsql/data

[global]
repo1-path=/app/pgsql/backup
# 保留3个完整的备份
repo1-retention-full=3
# 备份快速启动
start-fast=y
# 可以启用并行来加快速度，但执行备份阶段一般不需要（因为可能CPU不足的话会影响数据库服务器性能），执行恢复阶段可以考虑打开（恢复阶段PG已关闭）
# process-max=3

[global:archive-push]
compress-level=3
```
### 创建存储空间
```shell
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info stanza-create
2023-04-07 09:59:41.586 P00   INFO: stanza-create command begin 2.45: --exec-id=11377-f2a3f392 --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --stanza=demoll /
2023-04-07 09:59:42.205 P00   INFO: stanza-create for stanza 'demo' on repo1
2023-04-07 09:59:42.215 P00   INFO: stanza-create command end: completed successfully (633ms)
```
会生成两个文件夹
![image.png](https://cdn.nlark.com/yuque/0/2023/png/273193/1680832840721-2232177e-8b7d-4753-a078-b5c461bf8b4e.png#averageHue=%2322201e&clientId=u9c182443-c89a-4&from=paste&height=324&id=ub9222a8b&originHeight=324&originWidth=1860&originalType=binary&ratio=1&rotation=0&showTitle=false&size=163201&status=done&style=none&taskId=u8529089e-f7a2-4bda-b6b0-dc6197d8d5a&title=&width=1860)

- 错误处理

可能会看到如下错误
```shell
# 错误信息
ERROR: [050]: unable to acquire lock on file '/tmp/pgbackrest/demo-archive.lock': Permission denied

# 处理，原因是使用root用户执行了stanza-create
rm -rf /tmp/pgbackrest
su - postgres
pgbackrest --stanza=demo --log-level-console=info stanza-create
```
### 检查配置
check命令验证**pgBackRest**和archive_command设置是否为指定节的归档和备份正确配置
```shell
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info check
2023-04-07 10:01:12.156 P00   INFO: check command begin 2.45: --exec-id=11395-2402cdf8 --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --stanza=demo
2023-04-07 10:01:12.779 P00   INFO: check repo1 configuration (primary)
2023-04-07 10:01:12.989 P00   INFO: check repo1 archive for WAL (primary)
2023-04-07 10:01:13.193 P00   INFO: WAL segment 00000001000000000000001A successfully archived to '/app/pgsql/backup/archive/demo/12-1/0000000100000000/00000001000000000000001A-8afb1420e4c8de401b2166cb0bfcf64ef6c77273.gz' on repo1
2023-04-07 10:01:13.194 P00   INFO: check command end: completed successfully (1041ms)
```
## 备份
### 全备
> 默认情况下**pgBackRest**将尝试执行增量备份。
> 但是，增量备份必须基于完整备份，并且由于不存在完整备份，**pgBackRest**运行了完整备份。
> 可指定 --type=full 进行全量备份

```shell
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info backup
2023-04-07 10:29:42.088 P00   INFO: backup command begin 2.45: --exec-id=11551-26a0d95b --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo --start-fast
WARN: no prior backup exists, incr backup has been changed to full
2023-04-07 10:29:42.829 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2023-04-07 10:29:43.934 P00   INFO: backup start archive = 00000001000000000000004D, lsn = 0/4D0065E0
2023-04-07 10:29:43.934 P00   INFO: check archive for prior segment 00000001000000000000004C
2023-04-07 10:29:54.889 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2023-04-07 10:29:55.092 P00   INFO: backup stop archive = 000000010000000000000050, lsn = 0/5040DE00
2023-04-07 10:29:55.103 P00   INFO: check archive for segment(s) 00000001000000000000004D:000000010000000000000050
2023-04-07 10:29:55.233 P00   INFO: new backup label = 20230407-102942F
2023-04-07 10:29:55.278 P00   INFO: full backup size = 135.2MB, file total = 1379
2023-04-07 10:29:55.278 P00   INFO: backup command end: completed successfully (13192ms)
2023-04-07 10:29:55.278 P00   INFO: expire command begin 2.45: --exec-id=11551-26a0d95b --log-level-console=info --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo
2023-04-07 10:29:55.288 P00   INFO: expire command end: completed successfully (10ms)
```
### 差异备份
> - 差异备份必须基于完整备份
> - 可以通过使用--type=full运行**备份**命令来执行完整备份

```shell
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info --type=diff backup
2023-04-07 10:34:28.645 P00   INFO: backup command begin 2.45: --exec-id=11583-b2cf5dca --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo --start-fast --type=diff
2023-04-07 10:34:29.372 P00   INFO: last backup label = 20230407-102942F, version = 2.45
2023-04-07 10:34:29.372 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2023-04-07 10:34:30.499 P00   INFO: backup start archive = 00000001000000000000005D, lsn = 0/5D0005A0
2023-04-07 10:34:30.499 P00   INFO: check archive for prior segment 00000001000000000000005C
2023-04-07 10:34:37.686 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2023-04-07 10:34:37.898 P00   INFO: backup stop archive = 00000001000000000000005F, lsn = 0/5F51C550
2023-04-07 10:34:37.909 P00   INFO: check archive for segment(s) 00000001000000000000005D:00000001000000000000005F
2023-04-07 10:34:38.031 P00   INFO: new backup label = 20230407-102942F_20230407-103429D
2023-04-07 10:34:38.128 P00   INFO: diff backup size = 108MB, file total = 1395
2023-04-07 10:34:38.128 P00   INFO: backup command end: completed successfully (9484ms)
2023-04-07 10:34:38.128 P00   INFO: expire command begin 2.45: --exec-id=11583-b2cf5dca --log-level-console=info --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo
2023-04-07 10:34:38.133 P00   INFO: expire command end: completed successfully (5ms)
```
### 获取备份信息

- 最早的备份将_始终_是完整备份（由标签末尾的F表示）
- 最新备份可以是完整备份、差异备份（以D结尾）或增量备份（以I结尾）
- database size:数据库的完整未压缩大小
- database backup size:数据库中实际备份的数据量（这些对于完整备份是相同的）
-  backup set size: 包括此备份中的所有文件以及从该备份还原数据库所需的存储库中的任何引用备份
- backup size: 仅包括此备份中的文件（这些对于完整备份也相同）
- **如果在pgBackRest**中启用了压缩，则存储库大小反映压缩后的文件大小。
```shell
[postgres@init ~]$ pgbackrest info
stanza: demo
    status: ok
    cipher: none

    db (current)
        wal archive min/max (12): 00000001000000000000004A/00000001000000000000006C

        full backup: 20230407-102942F
            timestamp start/stop: 2023-04-07 10:29:42 / 2023-04-07 10:29:54
            wal start/stop: 00000001000000000000004D / 000000010000000000000050
            database size: 135.2MB, database backup size: 135.2MB
            repo1: backup set size: 20.9MB, backup size: 20.9MB

        diff backup: 20230407-102942F_20230407-103429D
            timestamp start/stop: 2023-04-07 10:34:29 / 2023-04-07 10:34:37
            wal start/stop: 00000001000000000000005D / 00000001000000000000005F
            database size: 159MB, database backup size: 108MB
            repo1: backup set size: 28.6MB, backup size: 19.5MB
            backup reference list: 20230407-102942F
```
### 定时备份
> crontab 设置每周日 06:30 进行全量备份，周一至周六 06:30 进行差异备份

```shell
30 06  *   *   0     pgbackrest --type=full --stanza=demo backup
30 06  *   *   1-6   pgbackrest --type=diff --stanza=demo backup
```
### 备份注释信息
#### 添加注释
```shell
[postgres@init ~]$ pgbackrest --stanza=demo --annotation=备注="demo备份信息" --annotation=创建人=杨大大 --log-level-console=info --type=full backup
2023-04-07 13:15:09.193 P00   INFO: backup command begin 2.45: --annotation=备注=demo备份信息 --annotation=创建人=杨大大 --exec-id=12420-be875c8c --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo --start-fast --type=full
2023-04-07 13:15:09.911 P00   INFO: execute non-exclusive backup start: backup begins after the requested immediate checkpoint completes
2023-04-07 13:15:10.416 P00   INFO: backup start archive = 000000020000000100000007, lsn = 1/7000028
2023-04-07 13:15:10.416 P00   INFO: check archive for prior segment 000000020000000100000006
2023-04-07 13:15:46.420 P00   INFO: execute non-exclusive backup stop and wait for all WAL segments to archive
2023-04-07 13:15:46.622 P00   INFO: backup stop archive = 000000020000000100000007, lsn = 1/7000138
2023-04-07 13:15:46.624 P00   INFO: check archive for segment(s) 000000020000000100000007:000000020000000100000007
2023-04-07 13:15:46.643 P00   INFO: new backup label = 20230407-131509F
2023-04-07 13:15:46.693 P00   INFO: full backup size = 451.6MB, file total = 1882
2023-04-07 13:15:46.693 P00   INFO: backup command end: completed successfully (37501ms)
2023-04-07 13:15:46.693 P00   INFO: expire command begin 2.45: --exec-id=12420-be875c8c --log-level-console=info --repo1-path=/app/pgsql/backup --repo1-retention-full=3 --stanza=demo
2023-04-07 13:15:46.695 P00   INFO: repo1: expire full backup set 20230407-112231F, 20230407-112231F_20230407-112508I
2023-04-07 13:15:46.698 P00   INFO: repo1: remove expired backup 20230407-112231F_20230407-112508I
2023-04-07 13:15:46.725 P00   INFO: repo1: remove expired backup 20230407-112231F
2023-04-07 13:15:46.889 P00   INFO: repo1: 12-1 remove archive, start = 0000000100000001, stop = 000000020000000100000001
2023-04-07 13:15:46.889 P00   INFO: expire command end: completed successfully (196ms)
```
#### 查看注释
```shell
[postgres@init example]$ pgbackrest --stanza=demo --set=20230407-131509F info
stanza: demo
    status: ok
    cipher: none

    db (current)
        wal archive min/max (12): 000000020000000100000005/0000000200000001000000BF

        full backup: 20230407-131509F
            timestamp start/stop: 2023-04-07 13:15:09 / 2023-04-07 13:15:46
            wal start/stop: 000000020000000100000007 / 000000020000000100000007
            lsn start/stop: 1/7000028 / 1/7000138
            database size: 451.6MB, database backup size: 451.6MB
            repo1: backup set size: 121.7MB, backup size: 121.7MB
            database list: abc (16833), pgbenchdb (16384), postgres (14187)
            annotation(s)
                创建人: 杨大大
                备注: demo备份信息
```
#### 修改注释
```shell
[postgres@init example]$ pgbackrest --stanza=demo --set=20230407-131509F --annotation=创建人= --annotation=备份人=杨大仙 annotate

[postgres@init example]$ pgbackrest --stanza=demo --set=20230407-131509F info
stanza: demo
    status: ok
    cipher: none

    db (current)
        wal archive min/max (12): 000000020000000100000005/0000000200000001000000C7

        full backup: 20230407-131509F
            timestamp start/stop: 2023-04-07 13:15:09 / 2023-04-07 13:15:46
            wal start/stop: 000000020000000100000007 / 000000020000000100000007
            lsn start/stop: 1/7000028 / 1/7000138
            database size: 451.6MB, database backup size: 451.6MB
            repo1: backup set size: 121.7MB, backup size: 121.7MB
            database list: abc (16833), pgbenchdb (16384), postgres (14187)
            annotation(s)
                备份人: 杨大仙               #####  这里被更改了
                备注: demo备份信息
```
### 清理归档[不建议使用]
使用清理归档后会将其他的归档清除，备份仅能恢复到 info内限定的时间数据
```shell
防止删除多了，做一次差异备份
[postgres@init ~]$ pgbackrest --stanza=demo --type=diff --log-level-console=info backup

[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=detail --repo1-retention-archive-type=diff --repo1-retention-archive=1 expire
2023-04-07 15:07:13.725 P00   INFO: expire command begin 2.45: --exec-id=13164-67b8125e --log-level-console=detail --repo1-path=/app/pgsql/backup --repo1-retention-archive=1 --repo1-retention-archive-type=diff --repo1-retention-full=3 --stanza=demo
WARN: option 'repo1-retention-diff' is not set for 'repo1-retention-archive-type=diff'
      HINT: to retain differential backups indefinitely (without warning), set option 'repo1-retention-diff' to the maximum.
2023-04-07 15:07:13.732 P00 DETAIL: repo1: 12-1 archive retention on backup 20230407-131509F, start = 000000020000000100000007, stop = 000000020000000100000007
2023-04-07 15:07:13.732 P00 DETAIL: repo1: 12-1 archive retention on backup 20230407-142447F, start = 0000000200000001000000B4, stop = 0000000200000001000000BA
2023-04-07 15:07:13.732 P00 DETAIL: repo1: 12-1 archive retention on backup 20230407-143557F, start = 0000000200000001000000D2
2023-04-07 15:07:13.778 P00   INFO: repo1: 12-1 remove archive, start = 000000020000000100000008, stop = 0000000200000001000000B3
2023-04-07 15:07:13.781 P00   INFO: repo1: 12-1 remove archive, start = 0000000200000001000000BB, stop = 0000000200000001000000D1
2023-04-07 15:07:13.782 P00   INFO: expire command end: completed successfully (59ms)
```
## 恢复

- restore 命令默认使用第一个存储库中的最新备份，使用特定存储库需要指定（如：--repo=1）
- 需要最新备份以外的可以使用 --set 选项
### 全量恢复

- 默认使用最新的一个备份进行恢复
- 会一路回放到WAL流结束，也就是说备份点后的WAL也都会全部恢复，应用所有的WAL
- 适合硬件故障等情况
```shell
systemctl stop postgresql-12

# 先要清空数据目录
[postgres@init ~]$ find /app/pgsql/data/ -mindepth 1 -delete
[postgres@init ~]$ ll /app/pgsql/data/
total 0

# 执行恢复
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info restore
[postgres@init ~]$ 
[postgres@init ~]$ ll data/
total 100
-rw------- 1 postgres postgres   259 Apr  7 11:25 backup_label
drwx------ 7 postgres postgres    67 Apr  7 11:35 base
-rw------- 1 postgres postgres    30 Apr  7 00:00 current_logfiles
drwx------ 2 postgres postgres  4096 Apr  7 11:35 global
drwx------ 2 postgres postgres   110 Apr  7 11:35 log
drwx------ 2 postgres postgres  8192 Apr  7 11:35 pg_commit_ts
drwx------ 2 postgres postgres     6 Apr  7 11:35 pg_dynshmem
-rw------- 1 postgres postgres  4652 Apr  6 16:33 pg_hba.conf
......
```
### 恢复指定的数据库
演示：
1.创建两个测试数据库与表
```shell
# 建库
psql -c "create database test1;"
psql -c "create database test2;"

# 建表与写测试数据
psql -d test1 -c "create table test1_table (id int);insert into test1_table (id) values (1);"
psql -d test2 -c "create table test2_table (id int);insert into test2_table (id) values (1);"
```
2.执行备份（全量或增量）
```shell
[postgres@init ~]$ pgbackrest --stanza=demo --log-level-console=info --type=full backup
... 备份信息略

# 可以pgbackrest info后查看下对应的备份信息
[postgres@init ~]$ pgbackrest --stanza=demo --set=20230407-154748F info
stanza: demo
    status: ok
    cipher: none

    db (current)
        wal archive min/max (12): 0000000200000001000000B4/000000020000000200000095

        full backup: 20230407-154748F
            timestamp start/stop: 2023-04-07 15:47:48 / 2023-04-07 15:49:16
            wal start/stop: 00000002000000020000008D / 000000020000000200000093
            lsn start/stop: 2/8D000610 / 2/9306BF60
            database size: 956.3MB, database backup size: 956.3MB
            repo1: backup set size: 281.0MB, backup size: 281.0MB
            database list: abc (16833), pgbenchdb (16384), postgres (14187), test1 (25240), test2 (25241)
```
3.查看下当前数据文件的大小
```shell
[postgres@init backup]$ du -sh /app/pgsql/data/base/16384/    # pgbenchdb
1.1G    /app/pgsql/data/base/16384/
[postgres@init backup]$ du -sh /app/pgsql/data/base/25240     # test1
8.1M    /app/pgsql/data/base/25240
[postgres@init backup]$ du -sh /app/pgsql/data/base/25241     # test2
8.1M    /app/pgsql/data/base/25241
```
4.恢复单个库（test1）

- 其他数据库会被创建，但是无法查看数据

注意：内置数据库（template0、template1和postgres）总是被恢复
```shell
# 停止数据库
[root@init pgsql]# systemctl stop postgresql-12
# 执行恢复
[postgres@init ~]$ pgbackrest --stanza=demo --delta --db-include=test1 --type=immediate --target-action=promote restore
[postgres@init ~]$ 
```

- 其他数据库是无法访问的,实际上并没有恢复回来
```shell
postgres=# \c test2      # 无法访问
FATAL:  relation mapping file "base/25241/pg_filenode.map" contains invalid data
Previous connection kept
postgres=# \c test1      # 正常访问
You are now connected to database "test1" as user "postgres".
test1=#
test1=# select * from test1_table;
 id 
----
  1
(1 row)


# 数据文件大小，可以看到恢复实际大小的只有 test1
[postgres@init ~]$ du -sh /app/pgsql/data/base/16384/       # pgbenchdb
74M     /app/pgsql/data/base/16384/
[postgres@init ~]$ du -sh /app/pgsql/data/base/25240			  # test1
8.1M    /app/pgsql/data/base/25240
[postgres@init ~]$ du -sh /app/pgsql/data/base/25241				# test2
16K     /app/pgsql/data/base/25241
```
### 时间点恢复
示例数据
```sql
abc=# select * from t;
 id |              va               
----+-------------------------------
  1 | a
  2 | b
  3 | 11:24
  4 | 2023-04-10 09:17:34.507343+08
  5 | 2023-04-10 09:17:37.621956+08
(5 rows)
```
执行恢复，恢复到 2023-04-10 09:17:37
```shell
# 关闭
[root@init ~]# systemctl stop postgresql-12

# 恢复
[root@init ~]# sudo -u postgres pgbackrest --stanza=demo --delta --type=time "--target=2023-04-10 09:17:37" --log-level-console=info --target-action=promote restore
2023-04-10 09:47:23.359 P00   INFO: restore command begin 2.45: --delta --exec-id=24386-f090757f --log-level-console=info --pg1-path=/app/pgsql/data --repo1-path=/app/pgsql/backup --stanza=demo --target="2023-04-10 09:17:37" --target-action=promote --type=time
2023-04-10 09:47:23.394 P00   INFO: repo1: restore backup set 20230407-154748F, recovery will start at 2023-04-07 15:47:48
2023-04-10 09:47:23.395 P00   INFO: remove invalid files/links/paths from '/app/pgsql/data'
2023-04-10 09:47:26.744 P00   INFO: write updated /app/pgsql/data/postgresql.auto.conf
2023-04-10 09:47:26.747 P00   INFO: restore global/pg_control (performed last to ensure aborted restores cannot be started)
2023-04-10 09:47:26.748 P00   INFO: restore size = 956.3MB, file total = 2979
2023-04-10 09:47:26.748 P00   INFO: restore command end: completed successfully (3390ms)


```
恢复完成
```sql
abc=# select * from t;
 id |              va               
----+-------------------------------
  1 | a
  2 | b
  3 | 11:24
  4 | 2023-04-10 09:17:34.507343+08
(4 rows)
```
## 监控备份
> 可以使用SQL语句查询最后一次成功备份的信息，需要使用到两个pgbackrest提供的sql脚本

```shell
# 导入建表语句，仅需要导入一次
[postgres@init ~]$ psql -f /opt/pgbackrest-release-2.45/doc/example/pgsql-pgbackrest-info.sql 
CREATE SCHEMA
CREATE FUNCTION

# 登陆可看到多了个 monitor
postgres=# \dn
  List of schemas
  Name   |  Owner   
---------+----------
 monitor | postgres
 public  | postgres
(2 rows)

# 查看最后一次成功的备份时间和归档WAL信息
[postgres@init ~]$ psql -f /opt/pgbackrest-release-2.45/doc/example/pgsql-pgbackrest-query.sql 
  name  | last_successful_backup |    last_archived_wal     
--------+------------------------+--------------------------
 "demo" | 2023-04-07 11:25:36+08 | 000000010000000100000000
(1 row)
```
## 删除备份存储空间

- 删除存储空间等于删除所有备份信息
- 包括归档的日志信息
```shell
# 首先要注意更改 archive_command 的内容，因为对应存储空间被删除了

# 先停止
[postgres@init backup]$ pgbackrest --stanza=demo --log-level-console=info stop
2023-04-10 10:24:09.541 P00   INFO: stop command begin 2.45: --exec-id=24549-ab6eb95b --log-level-console=info --stanza=demo
2023-04-10 10:24:09.542 P00   INFO: stop command end: completed successfully (2ms)

# 再删除
[postgres@init backup]$ pgbackrest --stanza=demo --repo=1 --log-level-console=info stanza-delete
2023-04-10 10:24:14.304 P00   INFO: stanza-delete command begin 2.45: --exec-id=24550-a145cfb9 --log-level-console=info --pg1-path=/app/pgsql/data --repo=1 --repo1-path=/app/pgsql/backup --stanza=demo
2023-04-10 10:24:15.103 P00   INFO: stanza-delete command end: completed successfully (802ms)
```
