#!/bin/bash
set -x
ns=codis
if [ $(kubectl -n $ns get pods -l app=zk |grep Running |wc -l) == 0 ]; then
    echo "start create zookeeper cluster"
    kubectl -n $ns create -f zookeeper/zookeeper-service.yaml
    kubectl -n $ns create -f zookeeper/zookeeper.yaml
    while [ $(kubectl -n $ns get pods -l app=zk |grep Running |wc -l) != 3 ]; do sleep 2; done;
    echo "finish create zookeeper cluster"
fi

product_name="codis-cluster"
#product_auth="auth"
case "$1" in

### 清理原来codis遗留数据
cleanup)
    kubectl -n $ns delete -f .
    # 如果zookeeper不是在kurbernetes上，需要登陆上zk机器 执行 zkCli.sh -server {zk-addr}:2181 rmr /codis3/$product_name
    kubectl -n $ns exec -it zk-0 -- zkCli.sh -server zk-0:2181 rmr /codis3/$product_name
    ;;

### 创建新的codis集群
buildup)
    kubectl -n $ns delete -f .
    # 如果zookeeper不是在kurbernetes上，需要登陆上zk机器 执行 zkCli.sh -server {zk-addr}:2181 rmr /codis3/$product_name
    kubectl -n $ns exec -it zk-0 -- zkCli.sh -server zk-0:2181 rmr /codis3/$product_name
    kubectl -n $ns create -f codis-service.yaml
    kubectl -n $ns create -f codis-dashboard.yaml
    while [ $(kubectl -n $ns get pods -l app=codis-dashboard |grep Running |wc -l) != 1 ]; do sleep 2; done;
    kubectl -n $ns create -f codis-proxy.yaml
    kubectl -n $ns create -f codis-server.yaml
    servers=$(grep "replicas" codis-server.yaml |awk  '{print $2}')
    while [ $(kubectl -n $ns get pods -l app=codis-server |grep Running |wc -l) != $servers ]; do sleep 2; done;
    kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --rebalance --confirm
    kubectl -n $ns create -f codis-ha.yaml
    kubectl -n $ns create -f codis-fe.yaml
    sleep 60
    kubectl -n $ns exec -it codis-dashboard-0 -- redis-cli -h codis-proxy -p 19000 PING
    if [ $? != 0 ]; then
        echo "buildup codis cluster with problems, plz check it!!"
    fi
    ;;

### 扩容／缩容 codis proxy
scale-proxy)
    kubectl -n $ns scale rc codis-proxy --replicas=$2
    ;;

### 扩容／[缩容] codis server
scale-server)
    cur=$(kubectl -n $ns get statefulset codis-server |tail -n 1 |awk '{print $2}'|awk -F '/' '{print $2}'|bc)
    des=$2
    echo $cur
    echo $des
    if [ $cur -eq $des ]; then
        echo "current server == desired server, return"
    elif [ $cur -lt $des ]; then
        kubectl -n $ns scale statefulsets codis-server --replicas=$des
        while [ $(kubectl -n $ns get pods -l app=codis-server |grep Running |wc -l) != $2 ]; do sleep 2; done;
        kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --rebalance --confirm
    else
        echo "reduce the number of codis-server, does not support, plz wait"
        # while [ $cur > $des ]
        # do
        #    cur=`expr $cur - 2`
        #    gid=$(expr $cur / 2 + 1)
        #    kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --slot-action --create-some --gid-from=$gid --gid-to=1 --num-slots=1024
        #    while [ $(kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080  --slots-status |grep "\"backend_addr_group_id\": $gid" |wc -l) != 0 ]; do echo "waiting slot migrating..."; sleep 2; done;
        #    kubectl -n $ns scale statefulsets codis-server --replicas=$cur
        #    kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --remove-group --gid=$gid
        # done
        # kubectl -n $ns scale statefulsets codis-server --replicas=$des
        # kubectl -n $ns exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --rebalance --confirm
    fi

    ;;    

*)
    echo "wrong argument(s)"
    ;;

esac
