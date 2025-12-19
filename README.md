# snmp-scripts

Collection of Checking scripts for snmpd extension useded for snmp monitoring

## Usage

1. place in /etc/snmp/scripts

2. use in snmpd.conf
    e.g
    ```
    extend needrestart /usr/bin/sudo /usr/sbin/needrestart -p
    extend check_apt /usr/lib/nagios/plugins/check_apt
    ```

3. Modify your snmp Monitoring System to read new vaules 
    e.g.
    ```
    NET-SNMP-EXTEND-MIB::nsExtendOutputFull."check_apt"
    ```
