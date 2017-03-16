#!/bin/env ruby

###########################
# procnet_to_graphite.rb #
# phreakocious, 9/2015  #
########################

require 'socket'
require 'optparse'

$graphite_port = 2003
$graphite_prefix = 'netstat'
$debug = false

files = [ '/proc/net/snmp', '/proc/net/netstat' ]
counters = [ 'Tcp.RetransSegs', 'Tcp.AttemptFails', 'Tcp.EstabResets', 'Tcp.OutRsts', 'Tcp.InRsts',
             'Tcp.InErrs', 'Tcp.InCsumErrors', 'Tcp.CurrEstab', 'Tcp.ActiveOpens', 'Tcp.PassiveOpens',
             'TcpExt.TCPTimeWaitOverflow', 'TcpExt.RcvPruned', 'TcpExt.TCPBacklogDrop',
             'TcpExt.PruneCalled', 'TcpExt.ListenOverflows', 'TcpExt.ListenDrops', 'TcpExt.TCPTimeouts',
             'TcpExt.TCPMemoryPressures', 'TcpExt.TCPReqQFullDoCookies', 'TcpExt.TCPReqQFullDrop',
             'TcpExt.TCPRetransFail', 'TcpExt.TCPOFOQueue', 'TcpExt.TCPOFODrop', 'TcpExt.TCPOFOMerge' ]

ARGV << '-h' if ARGV.empty?

OptionParser.new do |o|
  o.banner = "Usage: #{$0} [-g HOST] [options]"
  o.on('-g', '--graphite-host HOST', 'hostname or IP address of graphite host to send metrics to') { |b| $graphite_host = b }
  o.on('-l', '--graphite-port PORT', "graphite listening port (defaults to #{$graphite_port})") { |b| $graphite_port = b.to_i }
  o.on('-x', '--graphite-prefix PREFIX', "prefix for metric names (defaults to #{$graphite_prefix})") { |b| $graphite_prefix = b }
  o.on('-d', '--debug', 'debug mode prints results but sends no metrics to graphite') { |b| $debug = b }
  o.on('-h', '--help', 'this help stuff') { puts o; exit }
  o.parse!
end

metrics = []
hostname = Socket.gethostname.tr('.', '_')  # . is a separator in graphite

files.each do |file|
  File.open(file, 'r') do |fh|
    while line = fh.gets do
      next unless line =~ /:/
      keys = line.tr(':', '').split
      category = keys.shift
      fh.gets
      vals = $_.gsub(/.*: /, '').split
      timestamp = Time.now().to_i
      keys.each_with_index do |k, i|
        key = category + "." + k
        next unless counters.include?(key)
        metrics << sprintf("%s.%s.%s %d %d\n", $graphite_prefix, hostname, key, vals[i], timestamp)
      end
    end
  end
end

abort metrics.join if $debug || ! $graphite_host  # Print and end here if we're running in test mode!

begin
  socket = TCPSocket.open($graphite_host, $graphite_port)
  socket.write(metrics.join)
  socket.close()
rescue Exception => e
  STDERR.puts "*** failed to send metrics to #{$graphite_host}:#{$graphite_port} - #{e.to_s} ***"
end

