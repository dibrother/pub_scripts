#!/bin/bash
source ./common.sh
source ./config.cnf

function install(){
local etcd_name="etcd$(echo ${local_ip}|awk -F . '{print $4}')"

    local etcd_initial_cluster=''
    local array=(${etcd_cluster_ip//,/ })
    echo "${array[0]}  ${array[1]} ${array[2]}"
}


WorkingDirectory=/var/lib/etcd/
