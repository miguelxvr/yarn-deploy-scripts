#/!/bin/bash
#
#	title           :deploy-hadoop2.sh
#	description     :Install Hadoop 2 
#	author		:Miguel Xavier <miguel.xavier@acad.pucrs.br> 
#	date            :Thu Apr  9 18:53:56 BRT 2015
#	version         :1.0
#	usage		:deploy-hadoop2.sh

source hadoop.env
source hadoop-xml-conf.sh

CMD_OPTIONS=$(getopt -n "$0"  -o hidkstucl --long "help,interactive,deploy,docker,start,terminate,uninstall,copy,hibench"  -- "$@")
if [ $? -ne 0 ];
then
  exit 1
fi
eval set -- "$CMD_OPTIONS"

copyall()
{
	[ ! -f $1 ] && echo "File $1 not found" && exit 1

	for dest in $all_hosts; do
		scp $1 $dest:$2
	done
}

executeall()
{
	for dest in $all_hosts; do
		ssh $dest $1 
        done
}

execute()
{
	ssh $1 $2
}

build_hibench()
{
        # Download Hibench from repository
        git clone https://github.com/intel-hadoop/HiBench.git $SRC_DIR/HiBench
        pushd $SRC_DIR/HiBench/bin
        ./build-all.sh
        popd
}

configure_hibench()
{
	# Configure Hibench to fit the environment
        sed -e s,HADOOP_HOME,${HADOOP_HOME},g confs/99-user_defined_properties.conf.template | \
        sed -e s,HDFS_MASTER,${nn}:9000,g | \
        sed -e s,SPARK_HOME,${SPARK_HOME},g | \
        sed -e s,SPARK_VERSION,${SPARK_VERSION},g | \
        sed -e s,STORM_HOME,${STORM_HOME},g | \
        sed -e s,KAFKA_HOME,${KAFKA_HOME},g | \
        sed -e s,N_NODES,${TOTAL_NODES},g | \
        sed -e s,N_CORES,${TOTAL_CPU},g | \
        sed -e s,TOTAL_MEMORY,`expr ${TOTAL_MEMORY_MB} - 2048`,g > $SRC_DIR/HiBench/conf/99-user_defined_properties.conf
}

download()
{
	wget -N --no-check-certificate https://www.apache.org/dist/hadoop/core/hadoop-"$HADOOP_VERSION"/hadoop-"$HADOOP_VERSION".tar.gz -P $SRC_DIR
	wget -N --no-check-certificate http://d3kbcqa49mib13.cloudfront.net/spark-$SPARK_VERSION.0-bin-hadoop2.6.tgz -P $SRC_DIR
	wget -N --no-check-certificate http://ftp.unicamp.br/pub/apache/storm/apache-storm-$STORM_VERSION/apache-storm-$STORM_VERSION.tar.gz -P $SRC_DIR
	wget -N --no-check-certificate http://ftp.unicamp.br/pub/apache/kafka/0.10.0.0/kafka_$KAFKA_VERSION.tgz -P $SRC_DIR
}

install()
{
	echo "Copying Hadoop $HADOOP_VERSION to all hosts..."
	copyall $SRC_DIR/hadoop-"$HADOOP_VERSION".tar.gz /tmp/

	echo "Copying Spark $SPARK_VERSION to all hosts..."
	copyall $SRC_DIR/spark-$SPARK_VERSION.0-bin-hadoop2.6.tgz /tmp/

	echo "Copying storm $STORM_VERSION to all hosts..."
	copyall $SRC_DIR/apache-storm-$STORM_VERSION.tar.gz /tmp/

	echo "Copying kafka $KAFKA_VERSION to all hosts..."
	copyall $SRC_DIR/kafka_$KAFKA_VERSION.tgz /tmp/

	echo "Extracting Hadoop $HADOOP_VERSION distribution on all hosts..."
	executeall "tar -zxf /tmp/hadoop-"$HADOOP_VERSION".tar.gz -C /tmp"

	echo "Extracting Spark $SPARK_VERSION distribution on all hosts..."
	executeall "tar -zxf /tmp/spark-$SPARK_VERSION.0-bin-hadoop2.6.tgz -C /tmp"

        echo "Extracting storm $STORM_VERSION distribution on all hosts..."
        executeall "tar -zxf /tmp/apache-storm-$STORM_VERSION.tar.gz -C /tmp"

        echo "Extracting kafka $KAFKA_VERSION distribution on all hosts..."
        executeall "tar -zxf /tmp/kafka_$KAFKA_VERSION.tgz -C /tmp"

	echo "Copying addons to Hadoop home ..."
	copyall addons/yarn-scheduler-co-location-1.0.0.jar $HADOOP_HOME/share/hadoop/yarn/
	executeall "echo log4j.logger.de.tuberlin.cit.yarn.scheduler=DEBUG >> $HADOOP_HOME/etc/hadoop/log4j.properties"

        echo "Setting JAVA_HOME and HADOOP_HOME environment variables on all hosts..."
        executeall "echo \"export JAVA_HOME=$JAVA_HOME\" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"

	echo "Creating HDFS data directories on NameNode host, Secondary NameNode host, and DataNode hosts..."
	executeall "mkdir -p $NN_DATA_DIR && chown $USER $NN_DATA_DIR"
	executeall "mkdir -p $SNN_DATA_DIR && chown $USER $SNN_DATA_DIR"
	executeall "mkdir -p $DN_DATA_DIR && chown $USER $DN_DATA_DIR"
	executeall "mkdir -p $HADOOP_INIT && chown $USER $HADOOP_INIT"

	echo "Creating log directories on all hosts..."
	executeall "mkdir -p $YARN_LOG_DIR && chown $USER $YARN_LOG_DIR"
	executeall "mkdir -p $HADOOP_LOG_DIR && chown $USER $HADOOP_LOG_DIR"
	executeall "mkdir -p $HADOOP_MAPRED_LOG_DIR && chown $USER $HADOOP_MAPRED_LOG_DIR"

	echo "Creating pid directories on all hosts..."
	executeall "mkdir -p $YARN_PID_DIR && chown $USER $YARN_PID_DIR"
        executeall "mkdir -p $HADOOP_PID_DIR && chown $USER $HADOOP_PID_DIR"
        executeall "mkdir -p $HADOOP_MAPRED_PID_DIR && chown $USER $HADOOP_MAPRED_PID_DIR"

	echo "Editing Hadoop environment scripts for log directories on all hosts..."
	executeall "export HADOOP_LOG_DIR=$HADOOP_LOG_DIR >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"
	executeall "export YARN_LOG_DIR=$YARN_LOG_DIR >> $HADOOP_HOME/etc/hadoop/yarn-env.sh"
	executeall "export HADOOP_MAPRED_LOG_DIR=$HADOOP_MAPRED_LOG_DIR >> $HADOOP_HOME/etc/hadoop/mapred-env.sh"

	echo "Editing Hadoop environment scripts for pid directories on all hosts..."
	executeall "export HADOOP_PID_DIR=$HADOOP_PID_DIR >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"
	executeall "export YARN_PID_DIR=$YARN_PID_DIR >> $HADOOP_HOME/etc/hadoop/yarn-env.sh"
	executeall "export HADOOP_MAPRED_PID_DIR=$HADOOP_MAPRED_PID_DIR >> $HADOOP_HOME/etc/hadoop/mapred-env.sh"

	echo "Creating base Hadoop XML config files..."
	create_config --file confs/core-site.xml
	put_config --file confs/core-site.xml --property fs.default.name --value "hdfs://$nn:9000"
	put_config --file confs/core-site.xml --property hadoop.http.staticuser.user --value "$HTTP_STATIC_USER"
	#to set free acess to manage file to produce logs
	put_config --file confs/core-site.xml --property hadoop.proxyuser.mapred.groups --value "*"
	put_config --file confs/core-site.xml --property hadoop.proxyuser.mapred.hosts --value "*"

	create_config --file confs/hdfs-site.xml
	put_config --file confs/hdfs-site.xml --property dfs.namenode.name.dir --value "$NN_DATA_DIR"
	put_config --file confs/hdfs-site.xml --property fs.checkpoint.dir --value "$SNN_DATA_DIR"
	put_config --file confs/hdfs-site.xml --property fs.checkpoint.edits.dir --value "$SNN_DATA_DIR"
	put_config --file confs/hdfs-site.xml --property dfs.datanode.data.dir --value "$DN_DATA_DIR"
	put_config --file confs/hdfs-site.xml --property dfs.namenode.http-address --value "$nn:50070"
	put_config --file confs/hdfs-site.xml --property dfs.namenode.secondary.http-address --value "$snn:50090"

	create_config --file confs/mapred-site.xml
	put_config --file confs/mapred-site.xml --property mapreduce.framework.name --value yarn
	put_config --file confs/mapred-site.xml --property mapreduce.jobhistory.address --value "$mr_hist:10020"
	put_config --file confs/mapred-site.xml --property mapreduce.jobhistory.webapp.address --value "$mr_hist:19888"
	put_config --file confs/mapred-site.xml --property yarn.app.mapreduce.am.staging-dir --value /mapred
#	put_config --file confs/mapred-site.xml --property mapred.child.java.opts --value -Xmx2048m

	create_config --file confs/yarn-site.xml
	put_config --file confs/yarn-site.xml --property yarn.nodemanager.aux-services --value mapreduce_shuffle
	put_config --file confs/yarn-site.xml --property yarn.nodemanager.aux-services.mapreduce.shuffle.class --value org.apache.hadoop.mapred.ShuffleHandler
	put_config --file confs/yarn-site.xml --property yarn.web-proxy.address --value "$yarn_proxy:8081"
	put_config --file confs/yarn-site.xml --property yarn.resourcemanager.scheduler.address --value "$rmgr:8030"
	put_config --file confs/yarn-site.xml --property yarn.resourcemanager.resource-tracker.address --value "$rmgr:8031"
	put_config --file confs/yarn-site.xml --property yarn.resourcemanager.address --value "$rmgr:8032"
	put_config --file confs/yarn-site.xml --property yarn.resourcemanager.admin.address --value "$rmgr:8033"
	put_config --file confs/yarn-site.xml --property yarn.resourcemanager.webapp.address --value "$rmgr:8088"

        put_config --file confs/yarn-site.xml --property yarn.nodemanager.resource.memory-mb --value $TOTAL_MEMORY_MB
        put_config --file confs/yarn-site.xml --property yarn.nodemanager.resource.cpu-vcores --value $TOTAL_CPU
        put_config --file confs/yarn-site.xml --property yarn.scheduler.maximum-allocation-mb --value $TOTAL_MEMORY_MB
        put_config --file confs/yarn-site.xml --property yarn.scheduler.maximum-allocation-vcores --value $TOTAL_CPU
	put_config --file confs/yarn-site.xml --property yarn.log-aggregation-enable --value true
        put_config --file confs/yarn-site.xml --property yarn.resourcemanager.scheduler.class --value de.tuberlin.cit.yarn.scheduler.FixedHostsScheduler
#        put_config --file confs/yarn-site.xml --property yarn.resourcemanager.scheduler.class --value org.apache.hadoop.yarn.server.resourcemanager.scheduler.capacity.CapacityScheduler

	if [ "x$1" = "xdocker" ]; then
		put_config --file confs/yarn-site.xml --property yarn.nodemanager.container-executor.class --value org.apache.hadoop.yarn.server.nodemanager.DockerContainerExecutor
		put_config --file confs/yarn-site.xml --property yarn.nodemanager.docker-container-executor.exec-name --value /usr/bin/docker
	fi

        #enable capacity Scheduler, if you changes without destroy enviorment, use: yarn rmadmin -refreshQueues
	#create_config --file confs/capacity-scheduler.xml

	# copy config files to hosts
	copy_conf_files

	echo "Formatting the NameNode..."
        execute $nn "$HADOOP_HOME/bin/hdfs namenode -format"
}

copy_conf_files()
{

        echo "Copying addons to Hadoop home ..."
        copyall addons/yarn-scheduler-co-location-1.0.0.jar $HADOOP_HOME/share/hadoop/yarn/

	echo "Copying base Hadoop XML config files to all hosts..."
        copyall confs/core-site.xml $HADOOP_CONF_DIR
        copyall confs/hdfs-site.xml $HADOOP_CONF_DIR
        copyall confs/mapred-site.xml $HADOOP_CONF_DIR
        copyall confs/yarn-site.xml $HADOOP_CONF_DIR
        copyall confs/capacity-scheduler.xml $HADOOP_CONF_DIR

        echo "Copying startup scripts to all hosts..."
        copyall init.d/hadoop-namenode $HADOOP_INIT
        copyall init.d/hadoop-secondarynamenode $HADOOP_INIT
        copyall init.d/hadoop-datanode $HADOOP_INIT
        copyall init.d/hadoop-resourcemanager $HADOOP_INIT
        copyall init.d/hadoop-nodemanager $HADOOP_INIT
        copyall init.d/hadoop-historyserver $HADOOP_INIT
        copyall init.d/hadoop-proxyserver $HADOOP_INIT
        copyall hadoop.env $HADOOP_INIT
}

start()
{
	echo "Starting Hadoop $HADOOP_VERSION services on all hosts..."
	execute $nn "chmod 755 $HADOOP_INIT/hadoop-namenode && $HADOOP_INIT/hadoop-namenode start"
	execute $nn "chmod 755 $HADOOP_INIT/hadoop-secondarynamenode && $HADOOP_INIT/hadoop-secondarynamenode start"
	execute $mr_hist "chmod 755 $HADOOP_INIT/hadoop-historyserver && $HADOOP_INIT/hadoop-historyserver start"
	execute $yarn_proxy "chmod 755 $HADOOP_INIT/hadoop-proxyserver && $HADOOP_INIT/hadoop-proxyserver start"
	executeall "chmod 755 $HADOOP_INIT/hadoop-datanode && $HADOOP_INIT/hadoop-datanode start"

	execute $rmgr "chmod 755 $HADOOP_INIT/hadoop-resourcemanager && $HADOOP_INIT/hadoop-resourcemanager start"
	executeall "chmod 755 $HADOOP_INIT/hadoop-nodemanager && $HADOOP_INIT/hadoop-nodemanager start"
	execute $rmgr "$HADOOP_HOME/bin/yarn rmadmin -refreshQueues"

	hdfs dfsadmin -safemode leave

	echo -e "-------------------------------------------------------------------------------------"
	echo -e "Add the following exports in user profile ($HOME/.bashrc) before running Hadoop applications:\n"
	echo -e "
	export JAVA_HOME=$JAVA_HOME
	export PATH=\$PATH:$HADOOP_HOME/bin/
	export HADOOP_PREFIX=$HADOOP_HOME
	export HADOOP_HOME=$HADOOP_HOME
	export YARN_CONF_DIR=$HADOOP_CONF_DIR"

	echo -e "\nCheck application status at http://$rmgr:8088"
	echo -e "Check HDFS status at http://$nn:50070\n"
	echo -e "Enjoy!"
	echo -e "-------------------------------------------------------------------------------------"
}

stop()
{
	echo "Stopping Hadoop $HADOOP_VERSION services on all hosts..." execute $nn "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-namenode && $HADOOP_INIT/hadoop-namenode stop"
	execute $nn "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-secondarynamenode && $HADOOP_INIT/hadoop-secondarynamenode stop"
	execute $mr_hist "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-historyserver && $HADOOP_INIT/hadoop-historyserver stop"
	execute $yarn_proxy "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-proxyserver && $HADOOP_INIT/hadoop-proxyserver stop"
	executeall "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-datanode && $HADOOP_INIT/hadoop-datanode stop"

	execute $rmgr "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-resourcemanager && $HADOOP_INIT/hadoop-resourcemanager stop"
	executeall "[ -d "$HADOOP_INIT" ] && chmod 755 $HADOOP_INIT/hadoop-nodemanager && $HADOOP_INIT/hadoop-nodemanager stop"
}

uninstall()
{
	echo "Removing Hadoop distribution tarball..."
	executeall "rm -f /tmp/hadoop-"$HADOOP_VERSION".tar.gz"

	echo "Removing Hadoop home directory..."
	executeall "rm -rf $HADOOP_HOME"
	executeall "rm -rf $HADOOP_USER_HOME"
	executeall "rm -rf /tmp/hsperfdata_$USER"
	executeall "rm -rf /tmp/Jetty_*"
	executeall "rm -rf $DN_DATA_DIR*"
}

load_variables()
{
	nn=$(cat $PBS_NODEFILE | uniq | head -n1)
	snn=$(cat $PBS_NODEFILE | uniq | head -n1)
	rmgr=$(cat $PBS_NODEFILE | uniq | head -n1)
	mr_hist=$(cat $PBS_NODEFILE | uniq | head -n1)
	yarn_proxy=$(cat $PBS_NODEFILE | uniq | head -n1)
	dns=$(cat $PBS_NODEFILE | uniq)
	nms=$(cat $PBS_NODEFILE | uniq)
	all_hosts=$(cat $PBS_NODEFILE | uniq)

        TOTAL_MEMORY=`head -n1 /proc/meminfo | sed 's/^.[^0-9]*\(.[^ ]*\).*/\1/g'`
        TOTAL_MEMORY_MB=`expr $TOTAL_MEMORY / 1024`
	TOTAL_NODES=$(cat $PBS_NODEFILE | uniq | wc -l)
        TOTAL_CPU=`cat /proc/cpuinfo | grep processor | awk '{print $3}' | tail -n 1`
        TOTAL_CPU=`expr $TOTAL_CPU + 1`
}

help()
{
cat << EOF
deploy-hadoop2.sh 
 
This script installs Hadoop 2 with basic data, log, and pid directories. Configure the
environment in file hadoop.env before deployment. 
 
USAGE:  deploy-hadoop2.sh [options]
 
OPTIONS:
   -d, --deploy           Deploy YARN on allocated hosts
                          
   -k, --docker           Deploy YARN on docker containers

   -s, --start            Start all YARN components: NameNode Secondary NameNode 
				DataNodes ResourceManager NodeManagers

   -c, --copy 		  Copy configuration files to all hosts

   -t, --terminate	  Stop all YARN components: NameNode Secondary NameNode 
                                DataNodes ResourceManager NodeManagers

   -u, --uninstall	  Uninstall YARN, removing all associated data

   -l, --hibench	  Download and configure HiBench based on the environment

   -h, --help             Show this message.
   
EXAMPLES: 
   Use values from the PBS: 
     install-hadoop2.sh -d
     install-hadoop2.sh --deploy
             
EOF
}

while true;
do
  case "$1" in

    -h|--help)
      help
      exit 0
      ;;
    -d|--deploy)
      load_variables
      download
      install
      configure_hibench
      start
      break
      ;;
    -k|--docker)
      load_variables
      download
      install "docker"
      start
      break
      ;;
    -s|--start)
      load_variables 
      start 
      break
      ;;
    -t|--terminate)
      load_variables
      stop
      break
      ;;
    -u|--uninstall)
      load_variables
      stop
      uninstall 
      break
      ;;
    -c|--copy)
      load_variables
      copy_conf_files
      break
      ;;
    -l|--hibench)
      load_variables
      build_hibench
      configure_hibench
      break
      ;;
    --)
      help
      break
      ;;
  esac
done

