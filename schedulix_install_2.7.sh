#!/bin/bash
#
#	schedulix_install.sh
#
#	Installs schedulix conveniently by doing everything needed on a virgin install
#	of a linux distribution.
#	It has be be run as root.
#
#	usage: sudo bash schedulix_install.sh
#
#	Currently only Ubuntu 14.04 is supported.
#
#	To execute first edit the parameter settings in the function setup_parameters() to adapt to your needs.
#	CONFIRMPARAMETERS has to be set to TRUE to confirm that you had a look at the settings.
#
#	This script builds schedulix from source fetched from github.
#	The Zope web application server is installed via python easy_install.
#
#	Thus a working internet connection is neccessary to run this script.
#
#	If it breaks somewhere (internet problems, user interrupt, script flaw, ...) it can be rerun.
#
#	This script installs mariadb for schedulix repository storage.
#
setup_parameters(){
	#
	# The linux user which owns the schedulix installation
	# If not exit it will be created for your with group also beeing owner.
	#
	export OWNER=schedulix
	#
	# The linux password of $OWNER set on creation of $OWNER if he does not exist
	#
	export OWNERPASSWORD=$OWNER
	#
	# The linux home directory of $OWNER
	#
	export OWNERHOME=/home/$OWNER
	#
	# The directory where everything should be installed to
	#
	export INSTALLTO=$OWNERHOME
	#
	# The schedulix version to install
	#
	export INSTALLVERSION=2.7
	#
	# The mariadb user owning schedulix repository
	#
	export DBUSER=schedulix
	#
	# The mariadb password of $DBUSER
	#
	export DBPASSWORD=schedulix
	#
	# The database used for repository storage
	#
	export DBNAME=schedulixdb
	#
	# The mariadb root user
	#
	export MYSQLROOTUSER=root
	#
	# The mariadb password of $MYSQLROOTUSER
	#
	export MYSQLROOTPASSWORD=root
	#
	# Decide whether examples are installed
	#
	export INSTALLEXAMPLES=TRUE
	#
	# Decide whether the Zope application server for schedulix web gui are installed
	#
	export INSTALLZOPE=TRUE
	#
	# Zope version to install
	#
	export ZOPE2VERSION=2.13.22
	#
	# Name of the Zope instance to install for schedulix web gui
	#
	export ZOPEINSTANCE=schedulixweb
	#
	# Zope admin user and initial weg gui admin
	#
	export ZOPEADMINUSER=sdmsadm
	#
	# Zoppe password of $ZOPEADMINUSER
	#
	export ZOPEADMINPASSWORD=sdmsadm
	#
	# Decide whether init.d scripts should be installed
	#
	export INSTALLINITD=TRUE
	#
	# Confirm you parameter settings above, must be set to TRUE before running the script
	#
	export CONFIRMPARAMETERS=FALSE
}


# Exit codes
export NOERROR=0
export OTHER=1 
export NOTROOT=2
export NOLSBRELEASE=3
export OSNOTSUPPORTED=4
export OSVERSIONNOTSUPPORTED=5
export PKGINSTALLFAIL=6
export CREATEUSERFAIL=7
export MKDIRINSTALLTOFAIL=8
export GITCLONEFAIL=9
export MAKEFAIL=10
export DBCREATEFAIL=11
export DBINITFAIL=12
export SERVERFAIL=13
export SDMSHFAIL=14
export ZOPEFAIL=15
export DBROOTPASSWORDFAIL=16
export CONFIRMFAIL=17

SCRIPTNAME=$0

exit_failure(){
        msg=$1
        code=$2
        echo $msg >&2
        if [ "$code" == "" ]
        then
                code=1
        fi
        exit $code
}

check_root(){
	user=`id -u -n`
	if [ $user != root ]
	then
		exit_failure "$SCRIPTNAME has to be executed as user root" $NOTROOT
	fi
}

setup_ubuntu(){
	if [ "$DISTRIB_RELEASE" == "14.04" ]
	then
		REQUIRED="openjdk-7-jdk jflex libswt-gtk-3-java-gcj libswt-gtk-3-java libjna-java libjna-java mariadb-server-5.5 libmysql-java git gawk g++ python-dev python-setuptools"
		export CLASSPATH=$CLASSPATH:/usr/share/ant/lib/jflex.jar
		export JAVAHOME=java-7-openjdk-amd64
		export SWTJAR=/usr/share/java/swt.jar
		export JNAJAR=/usr/share/java/jna.jar
		export JDBCJAR=/usr/share/java/mysql-connector-java.jar
	else
	        exit_failure "Currently only Ubuntu 14.04 supported" $OSVERSIONNOTSUPPORTED
	fi
}

check_linux_version(){
	echo "Checking for support linux flavour and version"
	if test -f /etc/lsb-release 2>/dev/null
	then
	        . /etc/lsb-release
		if [ "$DISTRIB_ID" == "Ubuntu" ]
		then
			setup_ubuntu
		else
		        exit_failure "Currently only Ubuntu Systems supported" $OSNOTSUPPORTED
		fi
	else
	        exit_failure "Linux Systems without /etc/lsb-release currently not supported" $NOLSBRELEASE
	fi
}

install_package(){
	echo "Installing $pkg"
	pkg=$1
	if echo "$pkg" | fgrep -i mariadb >/dev/null 2>&1
	then
		export DEBIAN_FRONTEND=noninteractive
	fi
	apt-get install -y $pkg
	ret=$?
	if [ "$?" != 0 ]
	then
		exit_failure "Failed to install required package $pkg" $PKGINSTALLFAIL
	fi
	if echo "$pkg" | fgrep -i mariadb >/dev/null 2>&1
	then
		if mysql --user=root --execute exit >/dev/null 2>&1
		then
			mysqladmin --user=root password $MYSQLROOTPASSWORD >/dev/null 2>&1
		else
			mysql --user=root --password=$MYSQLROOTPASSWORD --execute exit >/dev/null 2>&1
			if [ $? != 0 ]
			then
				exit_failure "MariaDB root password set does not match definition in this script, edit script and restart" $DBROOTPASSWORDFAIL
			fi
		fi
		unset DEBIAN_FRONTEND
	fi
}

install_required_packages(){
	echo "Installing required packages"
	for PKG in $REQUIRED
	do
		install_package $PKG
	done
	echo "Installing python virtualenv"
	easy_install virtualenv
	
}

create_owner(){
	echo "Creating user $OWNER"
	if getent passwd $OWNER >/dev/null
	then
		echo "User $OWNER already exists"
		return
	else
		useradd --home-dir $OWNERHOME --create-home --shell /bin/bash --user-group $OWNER --password $(openssl passwd -1 $OWNERPASSWORD)
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error creating user $OWNER (exit code $ret)" $CREATUSERFAIL
		fi 
	fi 
}

install_as_owner(){
	echo "Running commands to be executed as user $OWNER"
	sudo -E -u schedulix bash << "ENDSCRIPT"

exit_failure(){
        msg=$1
        code=$2
        echo $msg >&2
        if [ "$code" == "" ]
        then
                code=1
        fi
        exit $code
}

test -d $INSTALLTO
if [ $? != 0 ]
then
	mkdir -p $INSTALLTO
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error creating directory $INSTALLTO (exit code $ret)" $MKDIRINSTALLTOFAIL
	fi
fi
cd $INSTALLTO

HOME=$OWNERHOME
echo "Fetching schedulix source code from git"
if test -d schedulix-$INSTALLVERSION
then
	echo "schedulix-$INSTALLVERSION already exists, skipping git clone"
else
	git clone https://github.com/schedulix/schedulix.git -b v$INSTALLVERSION schedulix-$INSTALLVERSION
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "git clone failed (exit code $ret)" $GITCLONEFAIL
	fi
	ln -s schedulix-$INSTALLVERSION schedulix
fi

echo "Building schedulix source code from source"

cd $INSTALLTO/schedulix
export SDMSHOME=`pwd`
cd src
make # new
ret=$?
if [ $ret != 0 ]
then
	exit_failure "make new failed (exit code $ret)" $MAKEFAIL
fi
chmod 644 $INSTALLTO/schedulix/lib/BICsuite.jar

echo "Setting up and sourcing $INSTALLTO/etc/.bicsuiteenv"

mkdir $INSTALLTO/etc 2>/dev/null
echo "export BICSUITEHOME=$INSTALLTO/schedulix
export BICSUITECONFIG=$INSTALLTO/etc" > $INSTALLTO/etc/.bicsuiteenv
echo 'export PATH=$BICSUITEHOME/bin:$PATH
export SWTJAR=/usr/share/java/swt.jar
export JNAJAR=/usr/share/java/jna.jar' >> $INSTALLTO/etc/.bicsuiteenv

. $INSTALLTO/etc/.bicsuiteenv
grep "\. $BICSUITECONFIG/\.bicsuiteenv" $OWNERHOME/.bashrc >/dev/null
if [ $? != 0 ]
then 
	echo ". $BICSUITECONFIG/.bicsuiteenv" >> $OWNERHOME/.bashrc
fi

echo "Creating mysql user $DBUSER and repository database $DBNAME"

if mysql --user=$DBUSER --password=$DBPASSWORD --execute exit >/dev/null 2>&1
then
	echo "mysql user $DBUSER already exists, skipping database creation and initialization"
else
	mysql --user=$MYSQLROOTUSER --password="$MYSQLROOTPASSWORD" << ENDMYSQL
create user $DBUSER identified by '$DBPASSWORD';
create database $DBNAME;
grant all on $DBNAME.* to $DBUSER;
quit
ENDMYSQL
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error creating mysql user $DBUSER and/or repository database $DBNAME" $DBCREATEFAIL
	fi

	echo "Initializing repository database $DBNAME"

	cd $BICSUITEHOME/sql
	mysql --user=$DBUSER --password=$DBPASSWORD --database=$DBNAME --execute "source mysql/install.sql"
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error initializing repository database $DBNAME (exit code $ret)" $DBINITFAIL
	fi
fi

echo "Initializing config files in $INSTALLTO/etc"

cd $BICSUITEHOME/etc
for fff in *.template
do
	TRG=`basename $fff .template`;
	cp $fff $BICSUITECONFIG/$TRG;
done
cd $BICSUITECONFIG
echo "Updating $INSTALLTO/etc/bicsuite.conf"
mv bicsuite.conf $$.tmp
sed "s:BICSUITELOGDIR=.*:BICSUITELOGDIR=$INSTALLTO/log:" < $$.tmp > bicsuite.conf
rm $$.tmp
echo "Updating $INSTALLTO/etc/java.conf"
egrep -v '^SWTJAR=|^JNAJAR=' <java.conf > $$.tmp
sed "s:^JDBCJAR=.*:JDBCJAR=$JDBCJAR:" < $$.tmp > java.conf
rm $$.tmp
echo "Updating $INSTALLTO/etc/server.conf"
mv server.conf $$.tmp
HOSTNAME=`hostname`
sed "s:DbPasswd=.*:DbPasswd=$DBPASSWORD:
s:DbUrl=.*:DbUrl=jdbc\:mysql\:///$DBNAME:
s:DbUser=.*:DbUser=$DBUSER:
s:Hostname=.*:Hostname=$HOSTNAME:
s:JdbcDriver=.*:JdbcDriver=com.mysql.jdbc.Driver:" < $$.tmp > server.conf
rm $$.tmp

echo "Setting up $OWNERHOME/.sdmshrc"

echo 'User=SYSTEM
Password=G0H0ME
Timeout=0' > $OWNERHOME/.sdmshrc
chmod 600 $OWNERHOME/.sdmshrc

echo "Setting up $INSTALLTO/etc/sdmshrc"

echo 'Host=localhost
Port=2506' > $INSTALLTO/etc/sdmshrc
chmod 644 $INSTALLTO/etc/sdmshrc

echo "Creating log directory $INSTALLTO/log"

mkdir $INSTALLTO/log 2>/dev/null

echo "Starting schedulix server"

server-start
ret=$?
if [ $ret != 0 ]
then
	exit_failure "Error error starting schedulix server (exit code $ret)" $SERVERFAIL
fi

echo "Installing convenience objects"

sdmsh < $BICSUITEHOME/install/convenience.sdms
ret=$?
if [ $ret != 0 ]
then
	exit_failure "Error error installing convenience objects (exit code $ret)" $SDMSHFAIL
fi

if [ "$INSTALLEXAMPLES" = "TRUE" ]
then
	echo "Installing example jobservers"

	cd $BICSUITEHOME/install
	./setup_example_jobservers.sh
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error error installing of example jobservers (exit code $ret)" $SDMSHFAIL
	fi

	echo "Installing of example objects"

	sdmsh < setup_examples.sdms
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error error installing of example objects (exit code $ret)" $SDMSHFAIL
	fi

	echo "Adding xhost + to .profile to enable example jobservers to access the DISPLAY"

	grep "xhost +" $OWNERHOME/.profile >/dev/null
	if [ $? != 0 ]
	then 
		echo "
xhost + >/dev/null 2>&1" >>$OWNERHOME/.profile
	fi

	if [ $INSTALLINITD != TRUE ]
	then
		echo "Starting example jobservers"

		start_example_jobservers.sh
	fi
fi

if [ $INSTALLINITD == TRUE ]
then
	echo "Stopping schedulix server"

	server-stop
fi

if [ "$INSTALLZOPE" = "TRUE" ]
then
	echo "Installing the Zope web application server"

	mkdir $INSTALLTO/software 2>/dev/null
	cd $INSTALLTO/software
	if test -d Zope
	then
		echo "$INSTALLTO/software/Zope already exists, skipping Zope installation"
	else
		virtualenv --no-site-packages Zope
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error creating python virtualenv environment (exit code $ret)" $ZOPEFAIL
		fi
		cd Zope
		bin/easy_install -i http://download.zope.org/Zope2/index/$ZOPE2VERSION Zope2
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error during easy_install of Zope2 version $ZOPE2VERSION (exit code $ret)" $ZOPEFAIL
		fi
	fi

	echo "Creating the Zope instance for schedulix!web"

	if test -d $INSTALLTO/$ZOPEINSTANCE
	then
		echo "Zope instance $INSTALLTO/$ZOPEINSTANCE already exists, skipping Zope installation"
		if [ $INSTALLINITD != TRUE ]
		then
			"Echo try to start Zope instance if not yet running"
			$INSTALLTO/$ZOPEINSTANCE/bin/zopectl start
		fi
	else
		cd Zope
		bin/mkzopeinstance -d $INSTALLTO/$ZOPEINSTANCE -u $ZOPEADMINUSER:$ZOPEADMINPASSWORD
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error creating Zope instance for schedulix!web (exit code $ret)" $ZOPEFAIL
		fi

		echo "Setting of required files in Zope instance $INSTALLTO/$ZOPEINSTANCE"

		cd $INSTALLTO/schedulixweb
		mkdir Extensions
		cd Extensions
		ln -s $BICSUITEHOME/zope/*.py .
		cd ../Products
		ln -s $BICSUITEHOME/zope/BICsuiteSubmitMemory .
		cd ../import
		ln -s $BICSUITEHOME/zope/SDMS.zexp .

		echo "Staring up Zope instance $INSTALLTO/$ZOPEINSTANCE"

		$INSTALLTO/$ZOPEINSTANCE/bin/zopectl start
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error starting Zope instance $INSTALLTO/$ZOPEINSTANCE (exit code $ret)" $ZOPEFAIL
		fi
		sleep 2

		echo "Importing schedulix Zope Objects into Zope instance $INSTALLTO/$ZOPEINSTANCE"

		wget --quiet --user=$ZOPEADMINUSER --password=$ZOPEADMINPASSWORD --output-document=/dev/null "http://localhost:8080/manage_importObject?file=SDMS.zexp"
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error importing SDMS.zexp (exit code $ret)" $ZOPEFAIL
		fi
		rm cookies.txt 2>/dev/null
		wget --quiet --user=sdmsadm --password=sdmsadm --output-document=/dev/null --keep-session-cookies --save-cookies cookies.txt "http://localhost:8080/SDMS/Install?manage_copyObjects:method=Copy&ids:list=User&ids:list=Custom"
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error copying User and Custom Zope template folders from Zope /SDMS/install (exit code $ret)" $ZOPEFAIL
		fi
		wget --quiet --user=sdmsadm --password=sdmsadm --output-document=/dev/null --load-cookies cookies.txt "http://localhost:8080?manage_pasteObjects:method=Paste"
		ret=$?
		if [ $ret != 0 ]
		then
			exit_failure "Error pasting User and Custom Zope folders into Zope / (exit code $ret)" $ZOPEFAIL
		fi
		rm cookies.txt

		if [ $INSTALLINITD == TRUE ]
		then
			echo "Stopping Zope instance $INSTALLTO/$ZOPEINSTANCE"
	
			$INSTALLTO/$ZOPEINSTANCE/bin/zopectl stop
		fi
	fi
fi
ENDSCRIPT
	ret=$?
	if [ $ret != 0 ]
	then
		exit_failure "Error while running commands to be executed as user $OWNER" $ret
	fi
}

install_initd(){
	echo "Installing init.d scripts to startup schedulix at boot"

	echo "creating /etc/init.d/schedulix-server"
	cat > /etc/init.d/schedulix-server << "ENDSCRIPT"
#!/bin/bash
#
### BEGIN INIT INFO
# Provides:          schedulix-server
# Required-Start:    $remote_fs $syslog mysql
# Required-Stop:     $remote_fs $syslog
# Should-Start:      $network $named $time
# Should-Stop:       $network $named $time
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start and stop the schedulix Enterprise Job Scheduling server daemon
# Description:       Controls the schedulix server process
### END INIT INFO
#
ENDSCRIPT
	cat >> /etc/init.d/schedulix-server << ENDSCRIPT
. $INSTALLTO/etc/.bicsuiteenv
export INSTALLTO=$INSTALLTO
export HOME=$OWNERHOME
ENDSCRIPT
	cat >> /etc/init.d/schedulix-server << "ENDSCRIPT"
set -e
set -u
${DEBIAN_SCRIPT_DEBUG:+ set -v -x}

test -x $BICSUITEHOME/bin/server-start || exit 0
test -x $BICSUITEHOME/bin/server-stop || exit 0
test -x $BICSUITEHOME/bin/server-restart || exit 0

. /lib/lsb/init-functions

SELF=$(cd $(dirname $0); pwd -P)/$(basename $0)

# Safeguard (relative paths, core dumps..)
cd /
umask 077

case "${1:-''}" in
  'start')
	log_daemon_msg "Starting schedulix Enterprise Job Scheduling server" "schedulix!server"
	if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	then
	    log_progress_msg "already running"
	    log_end_msg 0
	else
	    # Start schedulix!server
	    su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;server-start" >/dev/null 2>&1
	    if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	    then
	        log_end_msg 0
	    else
                log_end_msg 1
	        log_failure_msg "Please take a look at the $OWNERHOME/log/BICserver.out.* files"
	    fi
	fi
	;;

  'stop')
	log_daemon_msg "Stopping schedulix Enterprise Job Scheduling server" "schedulix!server"
	if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	then
	    # Stop schedulix!server
	    su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;server-stop" >/dev/null 2>&1
	    log_end_msg 0
	else
	    log_progress_msg "not running"
	    log_end_msg 0
	fi
	;;

  'restart')
	log_daemon_msg "Restarting schedulix Enterprise Job Scheduling server" "schedulix!server"
	if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	then
	    # Stop schedulix!server
	    su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;server-stop" >/dev/null 2>&1
	fi
	# Start schedulix!server
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;server-start" >/dev/null 2>&1 >/dev/null 2>&1
	if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	then
	    log_end_msg 0
	else
            log_end_msg 1
	    log_failure_msg "Please take a look at the /home/schedulix/log/BICserver.out.* files"
	fi
	;;

  'reload'|'force-reload')
  	log_daemon_msg "Reloading schedulix!server not supported" "schedulix!server"
	log_end_msg 0
	;;

  'status')
	if fuser -s $INSTALLTO/log/BICserver.out 2>/dev/null
	then
	  log_action_msg "schedulix!server is up"
	else
	  log_action_msg "schedulix!server is down"
	  exit 3
	fi
  	;;

  *)
	echo "Usage: $SELF start|stop|restart|reload|force-reload|status"
	exit 1
	;;
esac
ENDSCRIPT
chmod 700 /etc/init.d/schedulix-server

	update-rc.d -f schedulix-server remove
	update-rc.d -f schedulix-server defaults
	service schedulix-server start

	if [ "$INSTALLEXAMPLES" = "TRUE" ]
	then
		cat > /etc/init.d/schedulix-example_jobserver << "ENDSCRIPT"
#!/bin/bash
#
### BEGIN INIT INFO
# Provides:          schedulix-example_jobserver
# Required-Start:    $remote_fs $syslog schedulix-server
# Required-Stop:     $remote_fs $syslog
# Should-Start:      $network $named $time
# Should-Stop:       $network $named $time
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start and stop the schedulix Enterprise Job Scheduling example jobserver agents
# Description:       Controls the schedulix example jobserver processes
### END INIT INFO
#
ENDSCRIPT
		cat >> /etc/init.d/schedulix-example_jobserver << ENDSCRIPT
. $INSTALLTO/etc/.bicsuiteenv
export INSTALLTO=$INSTALLTO
export HOME=$OWNERHOME
ENDSCRIPT
		cat >> /etc/init.d/schedulix-example_jobserver << "ENDSCRIPT"
set -e
set -u
${DEBIAN_SCRIPT_DEBUG:+ set -v -x}

. /lib/lsb/init-functions

SELF=$(cd $(dirname $0); pwd -P)/$(basename $0)

# Safeguard (relative paths, core dumps..)
cd /
umask 077

case "${1:-''}" in
  'start')
	log_daemon_msg "Starting schedulix Enterprise Job Scheduling example jobservers" "schedulix!example-jobservers"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;export DISPLAY=:0;start_example_jobservers.sh" >/dev/null 2>&1
	log_end_msg 0
	;;

  'stop')
	log_daemon_msg "Stopping schedulix Enterprise Job Scheduling example jobservers" "schedulix!example-jobservers"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;stop_example_jobservers.sh" >/dev/null 2>&1
	log_end_msg 0
	;;

  'restart')
	log_daemon_msg "Restarting schedulix Enterprise Job Scheduling example jobservers" "schedulix!example-jobservers"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;stop_example_jobservers.sh" >/dev/null 2>&1
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;export DISPLAY=:0;start_example_jobservers.sh" >/dev/null 2>&1
	log_end_msg 0
	;;

  'reload'|'force-reload')
  	log_daemon_msg "Reloading schedulix!example-jobservers not supported" "schedulix!example-jobservers"
	log_end_msg 0
	;;

  'status')
  	log_daemon_msg "Status of schedulix!example-jobservers not supported" "schedulix!example-jobservers"
	log_end_msg 0
	;;

  *)
	echo "Usage: $SELF start|stop|restart|reload|force-reload|status"
	exit 1
	;;
esac
ENDSCRIPT
chmod 700 /etc/init.d/schedulix-example_jobserver

		update-rc.d -f schedulix-example_jobserver remove
		update-rc.d -f schedulix-example_jobserver defaults
		service schedulix-example_jobserver start
	fi

	if [ "$INSTALLZOPE" = "TRUE" ]
	then
		mknod $INSTALLTO/log/zope.out p 2>/dev/null
		chmod 600 $INSTALLTO/log/zope.out
		chown $OWNER:$OWNER $INSTALLTO/log/zope.out
		cat > /etc/init.d/schedulix-web << "ENDSCRIPT"
#!/bin/bash
#
### BEGIN INIT INFO
# Provides:          schedulix-web
# Required-Start:    $remote_fs $syslog schedulix-server
# Required-Stop:     $remote_fs $syslog
# Should-Start:      $network $named $time
# Should-Stop:       $network $named $time
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start and stop the schedulix Enterprise Job Scheduling web gui
# Description:       Controls the schedulix web gui zope server
### END INIT INFO
#
ENDSCRIPT
		cat >> /etc/init.d/schedulix-web << ENDSCRIPT
#!/bin/bash
. $INSTALLTO/etc/.bicsuiteenv
export INSTALLTO=$INSTALLTO
export HOME=$OWNERHOME
export ZOPEINSTANCE=$ZOPEINSTANCE
ENDSCRIPT
		cat >> /etc/init.d/schedulix-web << "ENDSCRIPT"
set -e
set -u
${DEBIAN_SCRIPT_DEBUG:+ set -v -x}

. /lib/lsb/init-functions

SELF=$(cd $(dirname $0); pwd -P)/$(basename $0)

# Safeguard (relative paths, core dumps..)
cd /
umask 077

case "${1:-''}" in
  'start')
	log_daemon_msg "Starting schedulix Enterprise Job Scheduling webserver" "schedulix!web"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;scrolllog $INSTALLTO/log/zope.out -e $INSTALLTO/$ZOPEINSTANCE/bin/runzope" >/dev/null 2>&1
	log_end_msg 0
	;;

  'stop')
	log_daemon_msg "Stopping schedulix Enterprise Job Scheduling webserver" "schedulix!web"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;fuser -k -INT $INSTALLTO/log/zope.out" >/dev/null 2>&1
	log_end_msg 0
	;;

  'restart')
	log_daemon_msg "Restarting schedulix Enterprise Job Scheduling webserver" "schedulix!web"
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;fuser -k -INT $INSTALLTO/log/zope.out" >/dev/null 2>&1
	su - schedulix /bin/bash -c ". $BICSUITECONFIG/.bicsuiteenv;scrolllog $INSTALLTO/log/zope.out -e $INSTALLTO/$ZOPEINSTANCE/bin/runzope" >/dev/null 2>&1
	log_end_msg 0
	;;

  'reload'|'force-reload')
  	log_daemon_msg "Reloading schedulix!web not supported" "schedulix!web"
	log_end_msg 0
	;;

  'status')
  	log_daemon_msg "Status of schedulix!web not supported" "schedulix!web"
	log_end_msg 0
	;;

  *)
	echo "Usage: $SELF start|stop|restart|reload|force-reload|status"
	exit 1
	;;
esac
ENDSCRIPT
chmod 700 /etc/init.d/schedulix-web

		update-rc.d -f schedulix-web remove
		update-rc.d -f schedulix-web defaults
		service schedulix-web start
	fi
}

if [ $CONFIRMPARAMETERS != TRUE ]
then
		exit_failure "Parameters not confirmed. Edit this script and set CONFIRMPARAMETERS to TRUE" $CONFIRMFAIL	
fi

MYHOME=$HOME

check_root
setup_parameters
check_linux_version
install_required_packages
create_owner

# just to be save when rerun, we try to stop all left over servers
service schedulix-server stop >/dev/null 2>&1
service schedulix-example_jobserver stop >/dev/null 2>&1
service schedulix-web stop >/dev/null 2>&1
server-stop >/dev/null 2>&1
zopectl stop >/dev/null 2>&1

install_as_owner

grep "\. $INSTALLTO/etc/\.bicsuiteenv" $MYHOME/.bashrc >/dev/null
if [ $? != 0 ]
then 
	echo ". $INSTALLTO/etc/.bicsuiteenv" >> $MYHOME/.bashrc
fi

if  [ $INSTALLINITD == TRUE ]
then
	install_initd
fi

if [ "$INSTALLEXAMPLES" ]
then
	grep "xhost + >/dev/null 2>&1" $MYHOME/.profile >/dev/null
	if [ $? != 0 ]
	then 
		echo "
xhost + >/dev/null 2>&1" >>$MYHOME/.profile
	fi
	xhost + 
fi

echo "Schedulix installation completed"
if [ "$INSTALLZOPE" = "TRUE" ]
then
	echo "You can access the web gui at http://localhost:8080/SDMS"
	echo "Login as user 'sdmsadm' with its initial password 'sdmsadm'"
	echo "For security change that password in the web gui"
	echo "If you want to use the schedulix commandline tools, close and reopen your terminals"
	echo " or do a '. $INSTALLTO/etc/.bicsuiteenv'"
fi

exit $NOERROR



