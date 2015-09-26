# check_for_new_devices.sh
Check the local network for new devices and keep track of their IPs in a MySQL database.
Requirements:
- A MySQL server.
- arp-scan (will be installed if is a Debian or RedHat based Linux distribution).
- MySQL client (will be installed if is a Debian or RedHat based Linux distribution).
Installation:
If the user running the script has granted permissions to create a database, the script will do it. Otherwise create a database and add permissions to the user running the script (using the .my.cnf file in the home folder) and the script will do the rest.
