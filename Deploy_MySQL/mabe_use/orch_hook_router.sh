#!/bin/bash
set -e

# 此脚本用于在orch集群托管多个MySQL集群时,用于替换 /etc/orchestrator.conf.json 中的 orch_hook.sh
# 对应的 CLUSTER01 需要自定义
# 对应的调用 CHECK_RESULT 相关需要自行配置

isitdead=$1
cluster=$2
oldmaster=$3
newmaster=$4

# 传入集群IP + 集群hostname
CLUSTER01='192.168.66.166,192.168.66.167,test06,test07'
CLUSTER02='192.168.66.168,192.168.66.169,test08,test09'

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

# 用于判断orch传输过来的值是否属于传入集群的
function check_include(){
  local IN_CLUSTER=$1
  TAG='N'
  if [ ${IN_CLUSTER} ];then
    # print_message "Note" "检测传入的CLUSTER01，值为:[${IN_CLUSTER}]"
    OLD_IFS="$IFS"
    IFS=","
    ARR_NODES=(${IN_CLUSTER})
    IFS="$OLD_IFS"

    for i in ${ARR_NODES[@]};
    do
      #echo "i 值为 ${i} , oldmaster 值为 ${oldmaster} "
      if [[ ${oldmaster} == ${i} ]];then
         TAG='Y'
      fi
    done
  fi
  echo ${TAG}
}

CHECK_RESULT=`check_include ${CLUSTER01}`
if [[ ${CHECK_RESULT} == "Y" ]];then
  echo "调用hook_cluster1"
  /usr/local/orchestrator/orch_hook_cluster01.sh ${isitdead} ${cluster} ${oldmaster} ${newmaster}
fi

CHECK_RESULT2=`check_include ${CLUSTER02}`
if [[ ${CHECK_RESULT2} == "Y" ]];then
  echo "调用hook_cluster2"
  /usr/local/orchestrator/orch_hook_cluster02.sh ${isitdead} ${cluster} ${oldmaster} ${newmaster}
fi
