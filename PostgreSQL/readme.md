### 环境

* 环境：CentOS7
* PG-12
* 使用yum安装

### 功能

* 安装单机PG
* 安装高可用PG（基于patroni）
* 需要有VIP

```shell
# ./pg_install.sh 
Usage: ./pg_install.sh [OPTIONS]
  single                 安装单机版PG
  ha                     安装HA的PG，使用patroni组件
  etcd                   安装ETCD，ha版的
  clearall               清除部署PG相关的所有中间件与环境信息
  clear_etcd             清除 etcd 相关环境
  clear_pg               清除 PG 相关环境
```

### 安装单机

修改配置文件 config.cnf 后

```shell
./pg_install.sh single
```

### 安装高可用

1. 配置时间同步（略 ntpdate 或其他）

2. 配置hosts，将三台机器的hostname与IP配置进去（建议）

3. 修改配置文件 config.cnf

4. 安装 ETCD

   ```shell
   # 三台机器分别执行
   ./pg_install_ha.sh etcd
   ```

5. 安装PG

   ```shell
   # 计划作为主节点的
   ./pg_install.sh ha
   
   # 等待第一台安装完成后，后面两台分别执行
   ./pg_install.sh ha
   ```

6. 检查

   ```shell
   # 任意一台执行，结果输出如下
   [root@test155 pginstall]# patronictl -c /etc/patroni/patroni.yml list
   + Cluster: pgsql ---------+--------------+---------+----+-----------+
   | Member | Host           | Role         | State   | TL | Lag in MB |
   +--------+----------------+--------------+---------+----+-----------+
   | pg155  | 192.168.60.155 | Leader       | running | 11 |           |
   | pg156  | 192.168.60.156 | Replica 		 | running | 11 |         0 |
   | pg157  | 192.168.60.157 | Replica      | running | 11 |         0 |
   +--------+----------------+--------------+---------+----+-----------+
   
   # 检查 VIP 是否在主库上
   
   # 测试连接
   ```

   

### 安装其他版本PG

* 需要可联网或自行制作对应版本yum源

* pgbackrest 请自行打包替换为对应PG版本的

* 修改脚本参数 pg_install.sh

  ```shell
  # 需要修改pgbackrest_name为对应的打包上传的名称
  pgbackrest_name=pgbackrest12
  # yum 对应安装的版本路径
  pg_home=/usr/pgsql-12
  ```

  