#!/bin/env ruby

###########################
# ifstats_to_graphite.rb #
# phreakocious, 7/2015  #
########################

begin require 'snmp'; rescue abort("The snmp gem is missing.  Install it with 'gem install snmp'"); end
require 'optparse'
require 'thread'
require 'time'

$threads = 8
$poller_name = 'ifstats'       # metric names will be in the format
$graphite_prefix = 'ifstats'   #  graphite_prefix.hostname.interface_name.metric_name
$graphite_port = 2003          #  ifstats.bfr01_foo_com.TenGigabitEthernet-10-1.InErrors
$retries = 2                   # poller metrics will be:
$timeout = 4                   #  graphite_prefix.__poller_name.metric_name
$bulkwalk = true               #  ifstats.__ifstats.varbinds
$maxbulk = 10
$debug = false

# Defines which metrics in the SNMP table to pay attention to
$counters = [ 'ifInDiscards', 'ifInErrors', 'ifHCInOctets', 'ifHCInUcastPkts', 'ifHCInMulticastPkts', 'ifHCInBroadcastPkts', 'ifHCOutOctets', 'ifOutErrors',
              'ifOutDiscards', 'ifHCOutUcastPkts', 'ifHCOutMulticastPkts', 'ifHCOutBroadcastPkts', 'ipIfStatsHCInOctets', 'ipIfStatsHCOutOctets' ]

# $counters = [ 'ifInDiscards', 'ifInErrors', 'ifOutErrors', 'ifOutDiscards' ]  # or maybe you just care about errors...

$hosts = Queue.new
$mutex = Mutex.new
$metrics = []
$errors = 0
$varbinds = 0

OptionParser.new do |o|
  o.banner = "Usage: #{$0} -c COMMUNITY [-h HOST | -f FILE] [options]"
  o.on('-c', '--community COMMUNITY', 'SNMP community string for device(s)') { |b| $community = b }
  o.on('-h', '--host HOST', 'hostname or IP address of device to poll')  { |b| abort "Error: -d and -f cannot be specified together." unless $hosts.empty?; $hosts << b }
  o.on('-f', '--file FILE', 'file containing a list of devices to poll') { |b| abort "Error: -d and -f cannot be specified together." unless $hosts.empty? ; handle_file(b) }
  o.on('-g', '--graphite-host HOST', 'hostname or IP address of graphite host to send metrics to') { |b| $graphite_host = b }
  o.on('-l', '--graphite-port PORT', "graphite listening port (defaults to #{$graphite_port})") { |b| $graphite_port = b.to_i }
  o.on('-x', '--graphite-prefix PREFIX', "prefix for metric names (defaults to #{$graphite_prefix})") { |b| $graphite_prefix = b }
  o.on('-p', '--parallel THREADS', "number of poller threads to run in parallel (defaults to #{$threads})") { |b| $threads = b.to_i }
  o.on('-n', '--name NAME', "identifier for this poller (for multiple instances) (defaults to #{$poller_name})") { |b| $poller_name = b }
  o.on('-r', '--retries RETRIES', "number of retries after a timeout (defaults to #{$retries})") { |b| $retries = b.to_i }
  o.on('-t', '--timeout TIMEOUT', "number of seconds to wait for a response (defaults to #{$timeout})") { |b| $timeout = b.to_i }
  o.on('-m', '--maxbulk VARBINDS', "maximum varbinds per-host to request in bulk (defaults to #{$maxbulk})") { |b| $maxbulk = b.to_i }
  o.on('-b', '--bulkwalk', "do bulk requests for SNMP (much more efficient) (defaults to #{$bulkwalk})") { |b| $bulkwalk = b }
  o.on('-d', '--debug', 'debug mode prints results but sends no metrics to graphite') { |b| $debug = b }
  abort o.to_s if ARGV.empty? || ARGV.last == '-h'
  o.parse!
end

def poll_host(host)
  host_metrics = []
  ts_host_start = Time.now.to_i
  $0 = "ifstats_to_graphite.rb: polling #{host}"  # Change the process name to prevent the community string from appearing in top/ps (sadly cannot do this per-thread in older ruby)
  puts "polling #{host}" if $debug
  iftables = snmptable(host, 'ifTable').deep_merge(snmptable(host, 'ifXTable'))
  host.tr!('.', '_')  # Clean up the hostname because . is a separator in graphite

  iftables.each do |ifindex, ifentry|
    next unless ifentry['ifAdminStatus'] == '1' && ifentry['ifOperStatus'] == '1'  # Skip interfaces that are admin or operationally down
    ifname = ifentry['ifDescr'].tr('/: ', '-').tr('"', '')                         # Clean up the interface name a bit

    $counters.each do |counter|
      next unless ifentry[counter]                # Maybe one is unsupported or missing?  Let's not send garbage to graphite or fail unspectacularly.
      counter_name = counter.gsub(/if(HC)?/, '')  # Clean up the counter name a bit
      host_metrics << sprintf("%s.%s.%s.%s %d %d\n", $graphite_prefix, host, ifname, counter_name, ifentry[counter], Time.now.to_i)
    end
  end  # iftables.each

  ts_host_end = Time.now.to_i
  host_time = ts_host_end - ts_host_start

  host_metrics << sprintf("%s.%s.__metrics %d %d\n", $graphite_prefix, host, host_metrics.length, ts_host_end)
  host_metrics << sprintf("%s.%s.__polltime %d %d\n", $graphite_prefix, host, host_time, ts_host_end)
  return host_metrics
end  # poll_host

host_count = $hosts.length
$threads = $threads > host_count ? host_count : $threads  # Don't spawn more threads than hosts to poll cuz that's wasteful
ts_polls_start = Time.now.to_i

thread_pool = Array.new($threads) do
  Thread.new do
    while (host = $hosts.shift(true) rescue nil) do
      host_metrics = poll_host(host)
      $mutex.synchronize { $metrics += host_metrics }  # Push metrics into global array in a thread-safe manner
    end
  end  # Thread.new
end

thread_pool.each(&:join)  # Pause main thread execution until all the others are done

ts_polls_end = Time.now.to_i
polls_time = ts_polls_end - ts_polls_start

$metrics << sprintf("%s.__%s.metrics %d %d\n", $graphite_prefix, $poller_name, $metrics.length, ts_polls_end)
$metrics << sprintf("%s.__%s.totaltime %d %d\n", $graphite_prefix, $poller_name, polls_time, ts_polls_end)
$metrics << sprintf("%s.__%s.varbinds %d %d\n", $graphite_prefix, $poller_name, $varbinds, ts_polls_end)
$metrics << sprintf("%s.__%s.threads %d %d\n", $graphite_prefix, $poller_name, $threads, ts_polls_end)
$metrics << sprintf("%s.__%s.errors %d %d\n", $graphite_prefix, $poller_name, $errors, ts_polls_end)
$metrics << sprintf("%s.__%s.hosts %d %d\n", $graphite_prefix, $poller_name, host_count, ts_polls_end)

abort $metrics.join if $debug || ! $graphite_host  # Print and end here if we're running in test mode!

$metrics.each_slice(10) do |metric_set|  # Sending too many things to graphite at once makes it angry.
  begin
    socket = TCPSocket.open($graphite_host, $graphite_port)
    socket.write(metric_set.join)
    socket.close()
  rescue Exception
     puts_err "failed to send metrics to #{$graphite_host}:#{$graphite_port} - #{$!}"
  end
end

### Helper functions go down here because I like Perl

BEGIN {
  def __snmpwalk(hostname, oid, community)  # Returns a recursive SNMP walk as an array of hashes
    rows = []
    SNMP::Manager.open(:host => hostname, :community => community, :timeout => $timeout, :retries => $retries) do |manager|
      begin
        manager.walk(oid) do |vb|
          rows << { :name => vb.name.to_s, :value => vb.value.to_s }
        end
      rescue
        puts_err "failed to walk oid #{oid} on host #{hostname}: #{$!}"
        increment_errors
      end
      increment_varbinds(rows.length)
      return rows
    end
  end

  def __snmpbulkwalk(hostname, oid, community)
    rows = []
    SNMP::Manager.open(:host => hostname, :community => community, :timeout => $timeout, :retries => $retries) do |manager|
      oid = manager.mib.oid(oid)
      next_oid = oid
      while next_oid.subtree_of?(oid)
        begin
          response = manager.get_bulk(0, $maxbulk, next_oid)
        rescue
          puts_err "failed to bulkwalk oid #{oid} on host #{hostname} - #{$!}"
          increment_varbinds(rows.length)
          increment_errors
          return rows
        end

        response.varbind_list.each do |vb|
          rows << { :name => vb.name.to_s, :value => vb.value.to_s }
        end

        varbind = response.varbind_list.last
        next_oid = varbind.name
      end
      increment_varbinds(rows.length)
      return rows
    end  # SNMP::Manager.open
  end

  def snmpwalk(hostname, oid, community = $community)
    if $bulkwalk
      return __snmpbulkwalk(hostname, oid, community)
    else
      return __snmpwalk(hostname, oid, community)
    end
  end

  def snmptable(hostname, oid, community = $community)  # Returns an SNMP table as a hash of hashes, keyed by index
    table = Hash.new{ |h, k| h[k] = Hash.new }
    snmpwalk(hostname, oid, community).each do |row|
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

  def puts_err(message)  # Using the mutex is cheap line buffering
    now = Time.now.utc.iso8601
    $mutex.synchronize { STDERR.puts "#{now} :: #{message}" }
  end

  def handle_file(input)  # Populates the queue.. handles - for stdin because ruby can be stupid.
    file = input == '-' ? STDIN : File.open(input)
    file.readlines.each { |line| $hosts << line.strip }
  end

  def increment_errors(count = 1)  # I really don't like these two functions, but making a Counter class was way more code
    $mutex.synchronize { $errors += count }
  end

  def increment_varbinds(count = 1)
    $mutex.synchronize { $varbinds += count }
  end

}
