#/bin/bash

STORAGEOS_RPM=storageos-2.4.0.0.e2817b5-1.x86_64.rpm
VIPR1_ADDR=172.17.0.1
GATEWAY=172.17.42.1
VIP=172.17.0.2
HOSTNAME=vipr1
NETMASK_BITS=16
DATA_DIR=${PWD}/vipr1
SETUP_DIR=${PWD}/data
CLEANUP_OLD=true

if ${CLEANUP_OLD}; then
    echo "Cleaning up old containers and NAT rules"
    docker stop $(docker ps --no-trunc -q)
    docker rm $(docker ps --no-trunc -aq)
    iptables -F DOCKER -t nat
fi

# Ensure that pipework is installed
/usr/bin/which pipework 2>&1 > /dev/null
if [ $? -ne 0 ]; then
    curl https://raw.githubusercontent.com/jpetazzo/pipework/master/pipework > /usr/local/bin/pipework
    chmod +x /usr/local/bin/pipework
fi

# Ensure that the /data/db:geodb:zk directories exist and have proper ownership
for i in db geodb zk ; do
  if [ ! -d ${DATA_DIR}/$i ]
    then 
       echo "creating directory /data/$i"
       mkdir ${DATA_DIR}/$i
  fi
  chmod 777 ${DATA_DIR}/$i
done

# Start the container
CONTAINER_ID=$(docker run --net=none -ti --privileged -v ${SETUP_DIR}:/coprhd:ro -v ${DATA_DIR}:/data:rw -d rustam9/coprhd-runtime)
echo "Created container ${CONTAINER_ID}"

# Configure the container and install storageos rpm
pipework docker0 -i eth0 ${CONTAINER_ID} ${VIPR1_ADDR}/${NETMASK_BITS}@${GATEWAY}
docker exec -it ${CONTAINER_ID} hostname ${HOSTNAME}
docker exec -it ${CONTAINER_ID} /bin/bash -c "echo ${VIPR1_ADDR} ${HOSTNAME} >> /etc/hosts"
docker exec -it ${CONTAINER_ID} /bin/bash -c "echo -e network_gateway=${GATEWAY}'\n'network_netmask=255.255.0.0'\n'network_prefix_length=64'\n'network_1_ipaddr=${VIPR1_ADDR}'\n'network_vip=${VIP}'\n'network_gateway6=::0'\n'network_1_ipaddr6=::0'\n'network_vip6=::0'\n'node_count=1'\n'node_id=${HOSTNAME} > /etc/ovfenv.properties"
docker exec -it ${CONTAINER_ID} rpm -ivh /coprhd/${STORAGEOS_RPM}

# Configure static NAT on the docker host
iptables -t nat -A  DOCKER -p tcp --dport 443 -j DNAT --to-destination ${VIP}:443
iptables -t nat -A  DOCKER -p tcp --dport 4443 -j DNAT --to-destination ${VIP}:4443

