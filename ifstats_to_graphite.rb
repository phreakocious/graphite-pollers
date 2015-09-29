#!/bin/env ruby

###########################
# ifstats_to_graphite.rb #
# phreakocious, 7/2015  #
########################

begin require 'snmp'; rescue abort("The snmp gem is missing.  Install it with 'gem install snmp'"); end
require 'optparse'
require 'thread'

$threads = 8
$graphite_prefix = 'ifstats'
$graphite_port = 2003
$testing = false
$retries = 2
$timeout = 4
$hosts = Queue.new
$mutex = Mutex.new
$metrics = []

ARGV << '-h' if ARGV.empty?  # Hax

OptionParser.new do |o|
  o.banner = "Usage: #{$0} -c COMMUNITY [-d DEVICE | -f FILE] [options]"
  o.on('-c', '--community COMMUNITY', 'SNMP community string for device(s)') { |b| $community = b }
  o.on('-d', '--device DEVICE', 'hostname or IP address of device to poll') { |b| abort "Error: -d and -f cannot be specified together." unless $hosts.empty?; $hosts << b }
  o.on('-f', '--file FILE', 'file containing a list of devices to poll') { |b| abort "Error: -d and -f cannot be specified together." unless $hosts.empty? ; File.readlines(b).each { |line| $hosts << line.strip }  }
  o.on('-g', '--graphite-host HOST', 'hostname or IP address of graphite host to send metrics to') { |b| $graphite_host = b }
  o.on('-l', '--graphite-port PORT', "graphite listening port (defaults to #{$graphite_port})") { |b| $graphite_port = b.to_i }
  o.on('-x', '--graphite-prefix PREFIX', "prefix for metric names (defaults to #{$graphite_prefix})") { |b| $graphite_prefix = b }
  o.on('-p', '--parallel THREADS', "number of poller threads to run in parallel (defaults to #{$threads})") { |b| $threads = b.to_i }
  o.on('-t', '--test', 'test mode prints results but sends no metrics to graphite') { |b| $testing = b }
  o.on('-h', '--help', 'this help stuff') { puts o; exit }
  o.parse!
end

# Defines which metrics in the SNMP table to pay attention to
$counters = [ 'ifInDiscards', 'ifInErrors', 'ifHCInOctets', 'ifHCInUcastPkts', 'ifHCInMulticastPkts', 'ifHCInBroadcastPkts', 'ifHCOutOctets', 'ifOutErrors', 
              'ifOutDiscards', 'ifHCOutUcastPkts', 'ifHCOutMulticastPkts', 'ifHCOutBroadcastPkts', 'ipIfStatsHCInOctets', 'ipIfStatsHCOutOctets' ]

def poll_host(host) 
  host_metrics = []
  $0 = "ifstats_to_graphite.rb: polling #{host}"  # Change the process name to prevent the community string from appearing in top/ps (sadly cannot do this per-thread in older ruby)
  puts "polling #{host}" if $testing
  timestamp = Time.now().to_i
  iftables = snmptable(host, $community, 'ifTable').deep_merge(snmptable(host, $community, 'ifXTable')) rescue nil  # This might fail occasionally... TODO: Better error handling could happen here.
  host.tr!('.', '_')  # Clean up the hostname because . is a separator in graphite

  iftables.each do |ifindex, ifentry|
    next unless ifentry['ifAdminStatus'] == '1' && ifentry['ifOperStatus'] == '1'  # Skip interfaces that are admin or operationally down
    ifname = ifentry['ifDescr'].tr('/: ', '-').tr('"', '')                         # Clean up the interface name a bit

    $counters.each do |counter|
      next unless ifentry[counter]  # Maybe one is unsupported or missing?  Let's not send garbage to graphite or fail unspectacularly.
      counter_name = counter.gsub(/if(HC)?/, '')                        # Clean up the counter name a bit
      metric = "#{$graphite_prefix}.#{host}.#{ifname}.#{counter_name}"  # Compose the name of the metric for graphite
      host_metrics << "#{metric} #{ifentry[counter]} #{timestamp}\n" 
    end

  end  # iftables.each

  return host_metrics
end  # poll_host

#TODO per-thread stats - number of hosts, ports, data points, execution time, failed snmpwalk/table calls, total execution time
thread_pool = Array.new($threads) do
  Thread.new do
    while (host = $hosts.shift(true) rescue nil) do
      host_metrics = poll_host(host)
      $mutex.synchronize { $metrics << host_metrics }  # Push metrics into global array in a thread-safe manner
    end
  end
end 

thread_pool.each(&:join)  # Pause main thread execution until all the others are done

abort $metrics.join if $testing || ! $graphite_host  # Print and end here if we're running in test mode!

$metrics.each_slice(30) do |metric_set|  # Sending too many things to graphite at once makes it angry.
  begin
    socket = TCPSocket.open($graphite_host, $graphite_port)
    socket.write(metric_set.join)
    socket.close()
  rescue Exception => e
    STDERR.puts "*** failed to send metrics to #{$graphite_host}:#{$graphite_port} - #{e.to_s} ***"
  end
end


### Helper functions go down here because I like Perl

BEGIN {
  def snmpwalk(hostname, community, oid)  # Returns a recursive SNMP walk as an array of hashes
    rows = []
    SNMP::Manager.open(:host => hostname, :community => community, :timeout => $timeout, :retries => $retries) do |manager|
      begin
        manager.walk(oid) do |row|
          rows << { :name => row.name.to_s, :value => row.value.to_s }
        end
        return rows
      rescue
        STDERR.puts "*** failed to walk oid #{oid} on host #{hostname}: #{$!} ***"
        return
      end
    end
  end

  def snmptable(hostname, community, oid)  # Returns an SNMP table as a hash of hashes, keyed by index
    table = Hash.new{ |h, k| h[k] = Hash.new }
    snmpwalk(hostname, community, oid).each do |row|
      column, index = row[:name].split('.').pop(2)  # Grab the index and counter name for tabularizationating
      column.gsub!(/.*::/, '')                      # Remove initial MIB information like IF-MIB::
      table[index][column] = row[:value]
    end
    return table
  end

  class ::Hash
    def deep_merge(second)  # Hash.merge can't properly handle a 'hash of hashes' structure, so monkeypatch it!
      merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      self.merge(second, &merger)
    end
  end
}
