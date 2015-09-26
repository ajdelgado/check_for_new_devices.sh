#!/bin/bash
DBNAME="known_devices"
DBTABLEKNOWDEVICES="known_devices"
DBTABLEIPS="devices_ips"
DBSERVER="localhost"
RECIPIENT=""
OUIDB="/var/lib/oui.txt"
DEBUG=0
function Message() {
	TEXT="$1"
	FORCE="$2"
	if [[ "$TEXT" != "" ]]; then
		logger -t "cleanup_users" -- "$TEXT"
		if [[ $DEBUG -gt 0 ]] || [[ "$FORCE" == "force" ]]; then
			CDATE=`date +"%Y/%m/%d %T"`
			echo -e "$CDATE $TEXT"
		fi
	fi
}
function CheckRequirement() {
	REQ="$1"
	Message "Checking for '$REQ'"
	RESULT=`whereis $REQ | awk '{print($2)}'`
	if [[ "$RESULT" == "" ]]; then
		DISTRIB_ID=`lsb_release -i | awk '{print($2)}'`
		if [[ "$DISTRIB_ID" == "" ]]; then
			if [[ -e /etc/redhat-release ]]; then
				DISTRIB_ID="RedHatEnterpriseES"
			fi
		fi
		case $DISTRIB_ID in
			"Ubuntu"|"Debian")
				Message "Installing $REQ with APT"
				sudo apt-get install $REQ
				;;
			"RedHatEnterpriseES")
				Message "Installing $REQ with YUM"
				sudo yum install $REQ
				;;
			"")
				Message "Couldn't find a distribution id, so you have to install $REQ manually." force
				exit 5
				;;
			*)
				Message "Distribution $DISTRIB_ID not handle, so you have to install $REQ manually." force
				exit 5
				;;
		esac
	else
		Message "$REQ found."
	fi
}
function CheckRequirements() {
	CheckRequirement arp-scan
	CheckRequirement logger
	CheckRequirement mysql	
}
function DeviceManufacturer() {
	DEVICEMAC=`echo "$1" |tr "[:lower:]" "[:upper:]" | sed "s/://g" - | cut -c1-6`
	if [[ "$DEVICEMAC" == "" ]]; then
		Message "Need a MAC address to find the manufacturer."
	else
		INDB=`cat $OUIDB | grep $DEVICEMAC| awk 'BEGIN {FS=")"} {print($2)}'`
		if [[ "$INDB" == "" ]]; then
			INDB="(unknwon)"
		fi
		echo $INDB
	fi
}
function SendQuery() {
	QUERY="$1"
	if [[ "$QUERY" == "" ]]; then
		Message "MySQL query must be provided."
	else
		echo "$QUERY" | mysql --host=$DBSERVER $DBNAME
		ERRCOD=$?
		if [[ "$ERRCOD" != "0" ]]; then
			echo "Returned error $ERRCOD."
		fi
		return $ERRCOD
	fi
}
function InstallDB() {
	Message "Creating database $DBNAME"
	echo "CREATE DATABASE $DBNAME;" | mysql --host=$DBSERVER
	ERRCOD=$?
	if [[ "$ERRCOD" != "0" ]]; then
		echo "Error creating database $DBANE. Check your .my.cnf file and provided credentials in the client section to the server $DBSERVER."
		exit 1
	else
		Message "Creating table $DBTABLEKNOWDEVICES"
		RESULT=`SendQuery "CREATE TABLE IF NOT EXISTS $DBTABLEKNOWDEVICES (
  id int(11) NOT NULL AUTO_INCREMENT,
  mac varchar(17) NOT NULL,
  last_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  name varchar(255) NOT NULL,
  manufacturer varchar(255) NOT NULL,
  last_ip varchar(15) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY mac (mac,name)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;"`
		ERRCOD=$?
		if [[ "$ERRCOD" != "0" ]]; then
			DEBUG=99
			Message "Error $ERRCOD while creating table $DBTABLEKNOWDEVICES. $RESULT".
			exit 2
		fi
		Message "Creating table $DBTABLEIPS"
		RESULT=`SendQuery "CREATE TABLE IF NOT EXISTS $DBTABLEIPS (
  id int(11) NOT NULL AUTO_INCREMENT,
  mac varchar(17) NOT NULL,
  date_found timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip varchar(15) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;"`
		ERRCOD=$?
		if [[ "$ERRCOD" != "0" ]]; then
			DEBUG=99
			Message "Error $ERRCOD while creating table $DBTABLEIPS. $RESULT".
			exit 3
		fi
	fi
}
function IsKnownDevice() {
	DEVICEMAC=$1
	if [[ "$DEVICEMAC" == "" ]]; then
		echo "Need a MAC address as first argument, to find out if is a know device."
	else
		INDB=`SendQuery "SELECT * FROM $DBTABLEKNOWDEVICES WHERE mac = '$DEVICEMAC';"| grep $DEVICEMAC`
		if [[ "$INDB" == "" ]]; then
			Message "Not found in database a device with MAC '$DEVICEMAC'"
			return 1
		else
			Message "Found a device with MAC address '$DEVICEMAC'. $INDB"
			return 0
		fi
	fi
	return 2
}
function IsSameIP() {
	DEVICEIP=$1
	DEVICEMAC=$2
	if [[ "$DEVICEIP" == "" ]] || [[ "$DEVICEMAC" == "" ]]; then
		echo "Need an IP address as first argument and a MAC address as second argument, to find out if is the same IP as last time."
	else
		INDB=`SendQuery "SELECT * FROM $DBTABLEKNOWDEVICES WHERE mac = '$DEVICEMAC' AND last_ip = '$DEVICEIP';" | grep $DEVICEMAC`
		if [[ "$INDB" == "" ]]; then
			Message "Not found a device with MAC '$DEVICEMAC' and last IP '$DEVICEIP'"
			return 1
		else
			Message "Found a device with MAC '$DEVICEMAC' and last IP '$DEVICEIP'. $INDB"
			return 0
		fi
	fi
	return 2
}
function SendAlert() {
	DEVICEIP=$1
	DEVICEMAC=$2
	DEVICEMANUFACTURER=$3
	if [[ "$DEVICEMAC" == "" ]]; then
		echo "Need a MAC address as first argument to alert $RECIPIENT."
	else
		if [[ "$RECIPIENT" != "" ]]; then
			Message "Alerting of new device with IP '$DEVICEIP' and MAC address '$DEVICEMAC' to $RECIPIENT"
			echo "Found a new device with IP '$DEVICEIP' and MAC address '$DEVICEMAC' (manufactured by $DEVICEMANUFACTURER) by $HOSTNAME." | mail -s "Found a new device with IP '$DEVICEIP' and MAC address '$DEVICEMAC' by $HOSTNAME." $RECIPIENT
		else
			Message "Not sending alert of new device with IP '$DEVICEIP' and MAC address '$DEVICEMAC', because it wasn't indicated any recipient."
		fi
	fi
}
function TestDB() {
	Message "Testing database installation"
	RESULT=`SendQuery "DESC $DBTABLEKNOWDEVICES;"`
	ERRCOD=$?
	if [[ "$ERRCOD" != "0" ]]; then
		Message "Error $ERRCOD while testing database. Result: $RESULT"
		InstallDB
	else
		Message "Database seems to be ok."
	fi
}
function Usage() {
	echo "$0 [--debug|--verbose|-d|-v] [--recipient|-r mail@exmaple.com] [--help|-h]"
	echo "--debug|--verbose|-d|-v           Increase debug information."
	echo "--recipient|-r mail@example.com   Send alerts to mail@example.com instead of default $RECIPIENT."
	echo "--help|-h                         Show this help"
}
for VAR in $*
do
	case "$1" in
		"--debug"|"-d"|"-v"|"--verbose")
			DEBUG=`expr $DEBUG + 1`
			Message "Debug level increased to $DEBUG"
			shift 1
			;;
		"--recipient"|"-r")
			RECIPIENT="$2"
			Message "The recipient for all mail will be '$RECIPIENT'"
			shift 2
			;;
		"--help"|"-h"|"-?"|"/?")
			Usage
			exit 0
			;;
		"")
			shift 1
			;;
		*)
			Message "Command line argument '$1' unknown" force
			shift 1
			;;
	esac
done
if [[ "$RECIPIENT" == "" ]]; then
	Message "No recipient indicated for alerts, so there won't be alerts."
fi
CheckRequirements
TestDB
sudo arp-scan -l | grep '[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}' | while read DEVICE
do
	DEVICEIP=`echo "$DEVICE" | awk '{print($1)}'`
	#Message "IP: $DEVICEIP"
	DEVICEMAC=`echo "$DEVICE" | awk '{print($2)}'`
	#Message "MAC: $DEVICEMAC"
	DEVICEMANUFACTURER=`DeviceManufacturer $DEVICEMAC`
	#Message "Manufacturer: $DEVICEMANUFACTURER"
	Message "Checking device '$DEVICEMAC'"
	ISKNOWN=`IsKnownDevice $DEVICEMAC`
	ERRCOD=$?
	if [[ "$ERRCOD" == "0" ]]; then
		Message "The device was already in the database"
		ISSAMEIP=`IsSameIP $DEVICEIP $DEVICEMAC`
		ERRCOD=$?
		if [[ "$ERRCOD" != "0" ]]; then
			Message "This is a different IP for this device.\n$ISSAMEIP"
			Message "Updating last IP for the device"
			SendQuery "UPDATE $DBTABLEKNOWDEVICES SET last_ip = '$DEVICEIP' WHERE mac = '$DEVICEMAC';"
			Message "Adding current device's IP"
			SendQuery "INSERT INTO $DBTABLEIPS (mac,ip) VALUES ('$DEVICEMAC','$DEVICEIP');"
		else
			Message "This is the last known IP of the device, so nothing else to do.\n$ISSAMEIP"
		fi
	else
		Message "Is not a known device.\n$ISKNOWN"
		Message "Adding device to known devices"
		SendQuery "INSERT INTO $DBTABLEKNOWDEVICES (mac,last_ip,manufacturer) VALUES ('$DEVICEMAC','$DEVICEIP','$DEVICEMANUFACTURER');"
		Message "Adding current device IP"
		SendQuery "INSERT INTO $DBTABLEIPS (mac,ip) VALUES ('$DEVICEMAC','$DEVICEIP');"
		Message "Seding alert to $RECIPIENT"
		SendAlert $DEVICEIP $DEVICEMAC $DEVICEMANUFACTURER
	fi
done
