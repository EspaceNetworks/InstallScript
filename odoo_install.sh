#!/usr/bin/env bash
################################################################################
# Script for installing Odoo on Ubuntu 14.04, 15.04 and 16.04 (could be used for other version too)
# Authors: Yenthe Van Ginneken, Chris Coleman (EspaceNetworks)
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu 16.04 server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

versiondate="2017-11-18.2"

##fixed parameters
OE_USER="odoo"
OE_HOME="/home/${OE_USER}"
OE_HOME_EXT="${OE_HOME}/${OE_USER}-server"
#The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
#Set to True if you want to install it, False if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
#Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
#Choose the Odoo version which you want to install. For example: 11.0, 10.0, 9.0 or saas-18. 
#When using 'master' the master version will be installed.
#IMPORTANT! This script installs packages and libraries that are needed by Odoo.
OE_VERSION="11.0"
# Set this to True if you want to install Odoo 11 Enterprise!
IS_ENTERPRISE="False"
#set the superadmin password
OE_SUPERADMIN="admin"
OE_CONFIG="${OE_USER}-server"
OE_RUN_SERVICE_AS_SUPERADMIN="False"
INSTALL_LOG="./install_log"
OE_ENTERPRISE_ADDONS="${OE_HOME}/enterprise/addons"
OE_GITHUB_ENTERPRISE_URL="https://www.github.com/odoo/enterprise"


##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltox installed, for a danger note refer to
## https://www.odoo.com/documentation/8.0/setup/install.html#deb ):
WKHTMLTOX_X64=https://downloads.wkhtmltopdf.org/0.12/0.12.4/wkhtmltox-0.12.4_linux-generic-amd64.tar.xz
WKHTMLTOX_X32=https://downloads.wkhtmltopdf.org/0.12/0.12.4/wkhtmltox-0.12.4_linux-generic-i386.tar.xz


#############
### FUNCTIONS
#############

function process_command_line {
	getopt --test > /dev/null
	if [[ $? -ne 4 ]]; then
	    echo "Sorry, cannot process command line, outdated version of getopt installed."
	    exit 1
	else
	
		OPTIND=1
	
		local OPTIONS=Ee
		#dfo:v
		local LONGOPTIONS=enterprise
		#debug,force,output:,verbose
	
		local E="n"
	
		# -temporarily store output to be able to check for errors
		# -e.g. use “--options” parameter by name to activate quoting/enhanced mode
		# -pass arguments only via   -- "$@"   to separate them correctly
		local PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
		if [[ $? -ne 0 ]]; then
		    # e.g. $? == 1
		    #  then getopt has complained about wrong arguments to stdout
		    exit 2
		fi
		# read getopt’s output this way to handle the quoting right:
		eval set -- "$PARSED"
	
		# now enjoy the options in order and nicely split until we see --
		while true; do
		    case "$1" in
		        #-d|--debug)
		        #    d=y
		        #    shift
		        #    ;;
		        #-f|--force)
		        #    f=y
		        #    shift
		        #    ;;
		        #-v|--verbose)
		        #    v=y
		        #    shift
		        #    ;;
		        #-o|--output)
		        #    outFile="$2"
		        #    shift 2
		        #    ;;
		        -E|-e|--enterprise)
		            E="y"
		            IS_ENTERPRISE="True"
		            shift
		            ;;
		        --)
		            shift
		            break
		            ;;
		        *)
		            echo "Option programming error"
		            exit 3
		            ;;
		    esac
		done
		
		# handle non-option arguments
		#if [[ $# -ne 1 ]]; then
		#    echo "$0: A single input file is required."
		#    exit 4
		#fi
		
		#echo "verbose: $v, force: $f, debug: $d, in: $1, out: $outFile"
		#echo "enterprise: $IS_ENTERPRISE"
	fi
}

function get_flavor_name {
	flavor="Community"
	if [[ $IS_ENTERPRISE == "True" ]]; then
	  flavor="Enterprise"
	fi
}

function remove_install_log {
  set +e
  rm ${INSTALL_LOG}
  set -e
}

function stop_odoo_server {
  set +e
  sudo service odoo-server stop
  set -e
}

function download_odoo {
  set +e
  sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/ >> $INSTALL_LOG
  set -e
}

function install_odoo_python_requirements_virtualenv {
  sudo apt-get install -y build-essential libxml2 libxslt1.1 libxml2-dev libxslt1-dev 
    python-libxml2 python-libxslt1 python-dev python-setuptools \
    libxml2-dev libxslt-dev libldap2-dev libsasl2-dev libssl-dev >> $INSTALL_LOG
  pip3 install virtualenv >> $INSTALL_LOG
  mkdir $OE_PYTHON_ENV >> $INSTALL_LOG
  virtualenv $OE_PYTHON_ENV -p /usr/bin/python3 >> $INSTALL_LOG
  source $OE_HOME/python_env/bin/activate && pip3 install -r $OE_HOME_EXT/requirements.txt >> $INSTALL_LOG
  deactivate
}

function update_server {
  sudo apt-get update >> $INSTALL_LOG
  sudo apt-get upgrade -y >> $INSTALL_LOG
}

function install_postgresql {
	sudo apt-get install postgresql -y >> $INSTALL_LOG
	sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true
}

function update_postgresql_template {
	set -e
	localedef -f UTF-8 -i en_US en_US.UTF-8 >> $INSTALL_LOG
	RUN_PSQL="sudo -u postgres psql -U postgres -X --set AUTOCOMMIT=off --set ON_ERROR_STOP=on --single-transaction "
	${RUN_PSQL} <<SQL
UPDATE pg_database SET encoding = pg_char_to_encoding('UTF8') WHERE datname = 'postgres';
UPDATE pg_database SET encoding = pg_char_to_encoding('UTF8') WHERE datname = 'template0';
UPDATE pg_database SET encoding = pg_char_to_encoding('UTF8') WHERE datname = 'template1';
SQL
}

function install_dependencies {
	# suds is for compatibility with Ubuntu 16.04. Will work on 14.04, 15.04 and 16.04
	sudo apt-get install -y python3 python3-pip wget git bzr python-pip \
	        gdebi-core node-clean-css node-less python-gevent python3-suds \
	        python-pypdf2 python-dateutil python-feedparser python-ldap python-libxslt1 \
	        python-lxml python-mako python-openid \
	        python-psycopg2 python-pybabel python-pychart python-pydot python-pyparsing \
	        python-reportlab python-simplejson python-tz python-vatnumber \
	        python-vobject python-webdav python-werkzeug python-xlwt python-yaml python-zsi \
	        python-docutils python-psutil python-mock python-unittest2 \
	        python-jinja2 python-pypdf python-decorator python-requests python-passlib python-pil \
	        build-essential libxml2 libxslt1.1 libxml2-dev libxslt1-dev python-libxml2 \
	        python-libxslt1 python-dev python-setuptools \
	        libxml2-dev libxslt-dev libldap2-dev libsasl2-dev libssl-dev >> $INSTALL_LOG
}

function upgrade_pip {
  sudo pip install --upgrade pip >> $INSTALL_LOG
  sudo pip3 install --upgrade pip >> $INSTALL_LOG
}

function install_python_libraries {
	sudo pip3 install pypdf2 Babel passlib Werkzeug decorator python-dateutil pyyaml psycopg2 \
	                  psutil html2text docutils lxml pillow reportlab \
	                  ninja2 requests gdata XlsxWriter vobject python-openid pyparsing pydot \
	                  mock mako Jinja2 ebaysdk feedparser xlwt psycogreen suds-jurko pytz \
	                  pyusb greenlet xlrd >> $INSTALL_LOG
}

function install_wkhtmltopdf {
	#--------------------------------------------------
	# Install Wkhtmltopdf if needed
	#--------------------------------------------------
  #pick up correct one from x64 & x32 versions:
  if [ "`getconf LONG_BIT`" == "64" ];then
      _url=$WKHTMLTOX_X64
  else
      _url=$WKHTMLTOX_X32
  fi
  sudo wget -nc $_url >> $INSTALL_LOG
  tar xf `basename $_url`
  sudo mv wkhtmltox/bin/* /usr/local/bin/
  rm -Rf wkhtmltox
  #sudo gdebi --n `basename $_url` >> $INSTALL_LOG
  set +e
  sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin >> $INSTALL_LOG
  sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin >> $INSTALL_LOG
  set -e
}

function create_odoo_system_user {
	sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER >> $INSTALL_LOG
	# FIX OWNERSHIP ON ODOO HOME DIR. THIS CAN CAUSE NODE TO BREAK AND FRONT END TO HAVE NO CSS OR IMAGES.
	chown $OE_USER. $OE_HOME >> $INSTALL_LOG
  set +e
	if [ $OE_RUN_SERVICE_AS_SUPERADMIN == "True" ]; then
	  #The user should also be added to the sudo'ers group.
	  sudo adduser $OE_USER sudo >> $INSTALL_LOG
	else
	  #Remove user from the sudo group, in case it was added on a previous install.
	  sudo deluser $OE_USER sudo >> $INSTALL_LOG
	fi
	set -e
}

function create_log_directory {
	set +e
	sudo mkdir /var/log/$OE_USER >> $INSTALL_LOG
	set -e
	sudo chown $OE_USER:$OE_USER /var/log/$OE_USER >> $INSTALL_LOG
}

function install_odoo_enterprise_addons {

  sudo su $OE_USER -c "mkdir -p $OE_ENTERPRISE_ADDONS" >> $INSTALL_LOG

  GITHUB_COMMAND="git clone --depth 1 --branch $OE_VERSION $OE_GITHUB_ENTERPRISE_URL $OE_ENTERPRISE_ADDONS"
  GITHUB_RESPONSE=$($GITHUB_COMMAND 2>&1) >> $INSTALL_LOG
  while [[ "$GITHUB_RESPONSE" == *"Authentication"* ]]; do
    echo "------------------------WARNING------------------------------"
    echo "Your authentication with Github has failed! Please try again."
    echo "In order to clone and install the Odoo enterprise version you" 
    echo "need to be an offical Odoo partner and you need access to"
    echo "http://github.com/odoo/enterprise."
    echo "TIP: Press ctrl+c to stop this script."
    echo "-------------------------------------------------------------"
    echo " "
    GITHUB_RESPONSE=$($GITHUB_COMMAND 2>&1) >> $INSTALL_LOG
  done
}

function install_enterprise_libraries {
  set -e
  sudo apt-get install -y nodejs npm >> $INSTALL_LOG
  sudo npm install -g less less-plugin-clean-css >> $INSTALL_LOG
  set +e
  sudo ln -s /usr/bin/nodejs /usr/bin/node >> $INSTALL_LOG
  set -e
}

function create_custom_module_dir {
  set +e
  sudo su $OE_USER -c "mkdir -p $OE_HOME/custom/addons" >> $INSTALL_LOG
  set -e
}

function set_permissions_home_dir {
  sudo chown -R $OE_USER:$OE_USER $OE_HOME/*  >> $INSTALL_LOG
}

function create_odoo_server_config_file {
  sudo touch ~/${OE_CONFIG}.conf
  sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> ~/${OE_CONFIG}.conf"
  sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> ~/${OE_CONFIG}.conf"
  sudo su root -c "printf 'xmlrpc_port = ${OE_PORT}\n' >> ~/${OE_CONFIG}.conf"
  sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}\n' >> ~/${OE_CONFIG}.conf"
  if [ $IS_ENTERPRISE = "True" ]; then
    sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons\n' >> ~/${OE_CONFIG}.conf"
  else
    sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> ~/${OE_CONFIG}.conf"
  fi
  sudo chown $OE_USER:$OE_USER ~/${OE_CONFIG}.conf  >> $INSTALL_LOG
  sudo chmod 640 ~/${OE_CONFIG}.conf  >> $INSTALL_LOG
  sudo mv ~/${OE_CONFIG}.conf /etc/${OE_CONFIG}.conf  >> $INSTALL_LOG
}

function create_startup_file {
  temp=~/temp0.sh
  rm -f $temp
  sudo touch $temp
  sudo su root -c "echo '#!/bin/sh' >> $temp"
  sudo su root -c "echo 'sudo -u $OE_USER $OE_HOME_EXT/${OE_USER}-bin --config=/etc/${OE_CONFIG}.conf' >> $temp"
  sudo chmod 755 $temp >> $INSTALL_LOG
  sudo chown $OE_USER. $temp >> $INSTALL_LOG
  mv $temp $OE_HOME_EXT/start.sh
}

function create_odoo_init_file {
  cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/bin:/sbin:/usr/bin
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/\${NAME}.pid
# Additional options that are passed to the Daemon.
DAEMON_OPTS="-c \$CONFIGFILE"
[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
[ -f \$PIDFILE ] || return 1
pid=\`cat \$PIDFILE\`
[ -d /proc/\$pid ] && return 0
return 1
}
case "\${1}" in
start)
echo -n "Starting \${DESC}: "
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
stop)
echo -n "Stopping \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
echo "\${NAME}."
;;
restart|force-reload)
echo -n "Restarting \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
sleep 1
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
*)
N=/etc/init.d/\$NAME
echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
exit 1
;;
esac
exit 0
EOF
}

function security_init_file {
  sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG  >> $INSTALL_LOG
  sudo chmod 755 /etc/init.d/$OE_CONFIG  >> $INSTALL_LOG
  sudo chown root: /etc/init.d/$OE_CONFIG  >> $INSTALL_LOG
}

function start_odoo_on_startup {
  sudo update-rc.d $OE_CONFIG defaults >> $INSTALL_LOG
}

function start_odoo {
sudo service odoo-server start >> $INSTALL_LOG
}

function show_odoo_status {
  sudo service odoo-server status
}

################################

cd ~
echo "Odoo Installer version $versiondate, by Yenthe Van Ginneken and Chris Coleman (EspaceNetworks)."
command_line_args=("$@")
process_command_line $command_line_args
get_flavor_name
echo "Installing: Odoo $OE_VERSION $flavor to $OE_HOME_EXT"

echo "---- Stop odoo server (if running) ----"
stop_odoo_server

#Remove previous install_log file
remove_install_log

echo -e "---- Update operating system ----"
update_server

echo -e "---- Install PostgreSQL Server + Create ODOO PostgreSQL User  ----"
install_postgresql

echo -e "---- Update postgresql template1 for UTF-8 charset ----"
update_postgresql_template

echo -e "---- Install Python 3 + pip3 + tool packages + python packages + other required--"
install_dependencies

echo -e "---- Download ODOO Server ----"
download_odoo

echo "---- Upgrade pip ----"
upgrade_pip

echo -e "---- Install python libraries ----"
install_python_libraries

### INSTALL PYTHON PACKAGES FROM REQUIREMENTS.TXT AND VIRTUALENV
### THIS WILL HALT (OUT OF MEMORY) BUILDING LXML ON 0.5 GB RAM SERVER, USING PREBUILT DISTRO PYTHON PACKAGES ABOVE INSTEAD.
###echo -e "---- Install python packages and virtualenv ----"
###install_odoo_python_requirements_virtualenv

if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "---- Install wkhtml and create shortcuts ----"
  install_wkhtmltopdf
else
  echo "---- Wkhtmltopdf isn't installed due to the choice of the user! ----"
fi

echo -e "---- Create ODOO system user ----"
create_odoo_system_user

echo -e "---- Create Log directory ----"
create_log_directory

if [ $IS_ENTERPRISE == "True" ]; then
  # Odoo Enterprise install!
  echo -e "---- Install ODOO Enterprise addons ----"
  set +e
  install_odoo_enterprise_addons
  echo -e "---- Added Enterprise addons under $OE_ENTERPRISE_ADDONS ----"
  set -e
  echo -e "---- Install Enterprise specific libraries + shortcut ----"
  install_enterprise_libraries
fi

echo -e "---- Create custom module directory ----"
create_custom_module_dir

echo -e "---- Set permissions on home folder ----"
set_permissions_home_dir

echo -e "* Create server config file"
create_odoo_server_config_file

echo -e "* Create startup file"
create_startup_file

echo -e "* Create init file"
create_odoo_init_file

echo -e "* Security Init File"
security_init_file

echo -e "* Start ODOO on Startup"
start_odoo_on_startup

echo -e "* Starting Odoo Service"
start_odoo

echo "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running. Specifications:"
echo "Port: $OE_PORT"
echo "User service: $OE_USER"
echo "User PostgreSQL: $OE_USER"
echo "Code location: $OE_HOME_EXT/"
echo "Addons folder: $OE_HOME_EXT/addons/"
if [[ $IS_ENTERPRISE == "True" ]]; then
  echo "ENTERPRISE addons folder: $OE_ENTERPRISE_ADDONS"
fi
echo "Start Odoo service: sudo service $OE_CONFIG start"
echo "Stop Odoo service: sudo service $OE_CONFIG stop"
echo "Restart Odoo service: sudo service $OE_CONFIG restart"
echo "-----------------------------------------------------------"
show_odoo_status
