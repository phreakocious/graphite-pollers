# graphite-pollers
Collection of scripts that shovel data into graphite.  Throw into cron and go!

#####ifstats_to_graphite.rb - A multi-threaded SNMP poller for IF-MIB interface statistics

Requires the snmp gem, additional counters can be added with an easy edit

```
$ ./ifstats_to_graphite.rb
Usage: ./ifstats_to_graphite.rb -c COMMUNITY [-h HOST | -f FILE] [options]
    -c, --community COMMUNITY        SNMP community string for device(s)
    -h, --host HOST                  hostname or IP address of device to poll
    -f, --file FILE                  file containing a list of devices to poll
    -g, --graphite-host HOST         hostname or IP address of graphite host to send metrics to
    -l, --graphite-port PORT         graphite listening port (defaults to 2003)
    -x, --graphite-prefix PREFIX     prefix for metric names (defaults to ifstats)
    -p, --parallel THREADS           number of poller threads to run in parallel (defaults to 8)
    -n, --name NAME                  identifier for this poller (for multiple instances) (defaults to ifstats)
    -r, --retries RETRIES            number of retries after a timeout (defaults to 2)
    -t, --timeout TIMEOUT            number of seconds to wait for a response (defaults to 4)
    -m, --maxbulk VARBINDS           maximum varbinds per-host to request in bulk (defaults to 10)
    -b, --bulkwalk                   do bulk requests for SNMP (much more efficient) (defaults to true)
    -d, --debug                      debug mode prints results but sends no metrics to graphite

$ ./ifstats_to_graphite.rb -d myswitch.foo.com -c public -d
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InDiscards 0 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InErrors 168133 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InOctets 356574694339561 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InUcastPkts 508394924186 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InMulticastPkts 690766140 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.InBroadcastPkts 416882247 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.OutOctets 154749245976266 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.OutUcastPkts 560080764584 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.OutMulticastPkts 651102595 1443281354
ifstats.myswitch_foo_com.TenGigabitEthernet1-1.OutBroadcastPkts 701814 1443281354
```



#####procnet_to_graphite.rb - Extract valuable linux TCP/UDP netstat data from /proc/net/

Additional files and counters of interest can be added with a simple tweak to the file.  Run this with a very short polling interval to catch some microbursts in action.

```
$ ./procnet_to_graphite.rb
Usage: ./procnet_to_graphite.rb [-g HOST | -d] [options]
    -g, --graphite-host HOST         hostname or IP address of graphite host to send metrics to
    -l, --graphite-port PORT         graphite listening port (defaults to 2003)
    -x, --graphite-prefix PREFIX     prefix for metric names (defaults to netstat)
    -d, --debug                      test mode prints results but sends no metrics to graphite
    -h, --help                       this help stuff

$ ./procnet_to_graphite.rb -d
netstat.mylinux_foo_com.Tcp.ActiveOpens 4127974 1443295704
netstat.mylinux_foo_com.Tcp.PassiveOpens 488481 1443295704
netstat.mylinux_foo_com.Tcp.AttemptFails 56140 1443295704
netstat.mylinux_foo_com.Tcp.EstabResets 156711 1443295704
netstat.mylinux_foo_com.Tcp.CurrEstab 121 1443295704
netstat.mylinux_foo_com.Tcp.RetransSegs 335093 1443295704
netstat.mylinux_foo_com.Tcp.OutRsts 185353 1443295704
netstat.mylinux_foo_com.TcpExt.TCPTimeWaitOverflow 0 1443295704
```

