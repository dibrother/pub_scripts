#!/bin/bash

############################## 通用参数声明 ##############################
# 获取脚本所在路径
current_dir=$(cd $(dirname $0); pwd)


############################## 基础通用函数 ##############################
# 打印
comm_print_note(){
    local msg=$1
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[32m[Note]\033[0m ${msg} "
}

comm_print_warning(){
    local msg=$1
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[33m[Warning]\033[0m ${msg}"
}

comm_print_error(){
    local msg=$1
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[31m[Error]\033[0m ${msg}"
}

##############################  检查，返回报错类函数 ##############################
# 判断参数是否为数字,不为数字则返回错误
function comm_check_param_is_number(){
  if [ "$1" -gt 0 ] 2>/dev/null ;then 
    :
  else 
    print_error "parameter is not a number."
    exit 1
  fi 
}

# 检查参数不为空
## 传入：
### $1 : 字符串，逗号分割，如："$a,$b,$c"
### $2 : 期望数值，如：3
### $3 : 备注信息，非必要，如："MySQL安装前参数检查"
function comm_check_params_not_empty(){
  local params=$1
  local params_hope_num=$2
  local note=${3}

  local array=(${params//,/ })
  local array_len=${#array[@]}
  if [ $array_len -ne $params_hope_num ];then
    print_error "parameter is empty. [${note}]"
    exit 1
  fi 

}

# 检查端口是否被占用
function comm_check_port_occupied(){
  local port=$1
  local check_value=$(ss -ntpl | grep -w ${port}|wc -l)
  if [ $check_value -gt 0 ];then
    print_error "Port [$port] is occupied."
    exit 1
  fi
}

############################## 判断，返回 0 或 1 的函数 ##############################
# 检查rpm包是否已安装(0:未安装  1:已安装)
function comm_is_rpm_install(){
   local s_name=$1 
   local check_value=$(rpm -qa|grep ${s_name}|wc -l)
   if [ $check_value -eq 0 ];then
     return 0
   else
     return 1
   fi
}

# 判断用户是否存在
## 传入：用户
function comm_is_user_exists(){
   local user=$1
   local check_value=$(cat /etc/passwd|grep ${user}|wc -l)
   if [ $check_value -eq 0 ];then
     return 0
   else
     return 1
   fi
}

# 检查是否可上外网(0:不可访问  1:可访问)
function comm_is_access_internet()
{
    local timeout=1
    local target=www.baidu.com
    #获取响应状态码
    local check_value=`curl -I -s --connect-timeout ${timeout} ${target} -w %{http_code} | tail -n1`

    if [ "x$check_value" = "x200" ]; then
        return 1
    else
        return 0
    fi
    return 0
}

############################## 系统初始化 ##############################
# 关闭 selinux
function comm_disable_selinux(){
  sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
  setenforce 0
}

# 关闭防火墙
function comm_do_stop_firewalld(){
  systemctl stop firewalld
  systemctl disable firewalld
}

# 优化设置资源限制
function comm_do_optimize_resource_limits(){
  cat >> /etc/security/limits.conf <<EOF
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
* soft nofile 65535
* hard nofile 65535
EOF

ulimit -n 65536
ulimit -u 65536
}

# 判断已优化内核参数（1：已优化  0：为优化）
## 仅针对判断
function comm_is_optimize_kernel_parameters(){
  local check_value=`cat /etc/security/limits.conf|grep soft| grep nofile|grep 65535|grep \*|wc -l`
  if [ $check_value -eq 0 ];then
    return 0  
  else
    return 1
  fi
}

# 优化内核参数
function comm_optimize_kernel_parameters() {
    local timestamp=`date +%F-%T`
    mv /etc/sysctl.conf /etc/sysctl.conf.bak-$timestamp
    cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_tw_buckets = 55000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1100 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 200000
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 2097152
net.core.wmem_max = 2097152
# 路由转发
net.ipv4.ip_forward = 1
# 开启反向路径过滤
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce=2
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
vm.swappiness = 0
kernel.sysrq = 1
vm.max_map_count = 262144
fs.inotify.max_user_instances = 8192
#net.netfilter.nf_conntrack_max = 524288
EOF
  # 立即生效
  sysctl -p

  echo "DefaultLimitNOFILE=65535" >> /etc/systemd/system.conf
  systemctl daemon-reload
}

# 未执行过优化的进行系统初始化优化
function comm_do_optimize_kernel_parameters(){
    is_optimize_kernel_parameters
    if [ $? -eq 0 ];then
       # 优化内核参数
       optimize_kernel_parameters
       # 优化设置资源限制
       do_optimize_resource_limits  
    fi
}


# 时间同步
function comm_ntpdate(){
    yum install -y ntpdate
    ntpdate ntp2.tencent.com
    hwclock -w
}

# 检查 IP 是否已存在[0：不存在 1:已存在]
## IP：需要检测的IP地址
## INTERFACE：网卡名称，如 ens33
check_ip_exists(){
  local IP=$1
  local INTERFACE=$2
  local chk_value=$(sudo ip addr show dev ${INTERFACE} to ${IP})
  if [ -n "$chk_value" ];then
    return 1
  else
    return 0
  fi
}

# arping检查 IP 是否已被占用[0：未占用 1:已占有]
check_ip_arp(){
  local IP=$1
  local INTERFACE=$2
  sudo arping -c 1 -I ${INTERFACE} ${IP}
  if [ $? -eq 0 ];then
    return 1
  else
    return 0
  fi
}

# 添加 VIP
cmd_vip_add(){
  if check_vip_exists && check_vip_arp;then
    sudo ip addr add  ${VIP} dev ${INF}
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} added"
  else
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} already be used,please check!"
  fi
}

# 删除 VIP
cmd_vip_del(){
  if ! check_vip_exists;then
    sudo ip addr del ${VIP}/32 dev ${INF}
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} removed"
  else
    echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} not exists,please check!"
  fi
}

############################## 工具类函数 ##############################
# 发送钉钉消息通知
#function comm_send_dingding(){
#   
#}
