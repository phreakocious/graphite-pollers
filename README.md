# graphite-pollers
Collection of scripts that shovel data into graphite.  Throw into cron and go!

#####ifstats_to_graphite.rb - A multi-threaded SNMP poller for IF-MIB interface statistics

Requires the snmp gem, additional counters can be added with an easy edit

```
$ ./ifstats_to_graphite.rb
Usage: ./ifstats_to_graphite.rb -c COMMUNITY [-d DEVICE | -f FILE] [options]
    -c, --community COMMUNITY        SNMP community string for device(s)
    -d, --device DEVICE              hostname or IP address of device to poll
    -f, --file FILE                  file containing a list of devices to poll
    -g, --graphite-host HOST         hostname or IP address of graphite host to send metrics to
    -l, --graphite-port PORT         graphite listening port (defaults to 2003)
    -x, --graphite-prefix PREFIX     prefix for metric names (defaults to ifstats)
    -p, --parallel THREADS           number of poller threads to run in parallel (defaults to 8)
    -t, --test                       test mode prints results but sends no metrics to graphite
    -h, --help                       this help stuff

$ ./ifstats_to_graphite.rb -d myswitch.foo.com -c public -t
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

Additional files and counters of interest can be added with a simple tweak to the file.  Run this with a 15 or 30 second polling interval to catch some microbursts in action.

```
$ ./procnet_to_graphite.rb 
Usage: ./procnet_to_graphite.rb [-g HOST | -t] [options]
    -g, --graphite-host HOST         hostname or IP address of graphite host to send metrics to
    -l, --graphite-port PORT         graphite listening port (defaults to 2003)
    -x, --graphite-prefix PREFIX     prefix for metric names (defaults to netstat)
    -t, --test                       test mode prints results but sends no metrics to graphite
    -h, --help                       this help stuff

$ ./procnet_to_graphite.rb -t
netstat.mylinux_foo_com.Tcp.ActiveOpens 4127974 1443295704
netstat.mylinux_foo_com.Tcp.PassiveOpens 488481 1443295704
netstat.mylinux_foo_com.Tcp.AttemptFails 56140 1443295704
netstat.mylinux_foo_com.Tcp.EstabResets 156711 1443295704
netstat.mylinux_foo_com.Tcp.CurrEstab 121 1443295704
netstat.mylinux_foo_com.Tcp.RetransSegs 335093 1443295704
netstat.mylinux_foo_com.Tcp.OutRsts 185353 1443295704
netstat.mylinux_foo_com.TcpExt.TCPTimeWaitOverflow 0 1443295704
```

