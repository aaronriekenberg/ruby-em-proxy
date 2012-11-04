#!/usr/bin/env ruby

require 'eventmachine'
require 'socket'

class ProxyRemoteConnection < EM::Connection

  def initialize(connectCompleteCallback, connectFailedCallback)
    super()
    @connectCompleteCallback = connectCompleteCallback
    @connectFailedCallback = connectFailedCallback
    @connectionString = nil
  end

  def connection_completed
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    remotePort, remoteIP = Socket.unpack_sockaddr_in(get_peername)
    @connectionString =
      "#{localIP}:#{localPort} -> #{remoteIP}:#{remotePort}"
    puts "connected #{@connectionString}"

    @connectCompleteCallback.call if not @connectCompleteCallback.nil?
    @connectFailedCallback = nil
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    puts "close #{@connectionString}" if not @connectionString.nil?
    @connectFailedCallback.call if not @connectFailedCallback.nil?
  end

end

class ProxyClientConnection < EM::Connection

  def initialize(remoteHostAndPort)
    super()
    @remoteHostAndPort = remoteHostAndPort
    @connectionString = nil
  end

  def post_init
    clientPort, clientIP = Socket.unpack_sockaddr_in(get_peername)
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    @connectionString =
      "#{clientIP}:#{clientPort} -> #{localIP}:#{localPort}"
    puts "accept #{@connectionString}"

    pause
    connectCompleteCallback = proc { start_proxy }
    connectFailedCallback = proc { close_connection }
    @proxyRemoteConnection =
      EM::connect(@remoteHostAndPort[:host], @remoteHostAndPort[:port],
                  ProxyRemoteConnection,
                  connectCompleteCallback, connectFailedCallback)
  end

  def start_proxy
    resume
    EM::enable_proxy(self, @proxyRemoteConnection, 65536)
    EM::enable_proxy(@proxyRemoteConnection, self, 65536)
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    puts "close #{@connectionString}" if not @connectionString.nil?
  end

end

def main
  hostPortRE = /^(.+):(\d+)$/
  hostAndPorts = ARGV.map do |arg|
    match = hostPortRE.match(arg)
    if match.nil?
      raise "Illegal argument '#{arg}'"
    end
    { :host => match[1], :port => match[2].to_i }
  end

  if hostAndPorts.length < 2
    puts "Usage: #{$0} <listen addr> [ <listen addr> ... ] <remote addr>"
    exit(1)
  end

  remoteHostAndPort = hostAndPorts.pop
  puts "remote address #{remoteHostAndPort[:host]}:#{remoteHostAndPort[:port]}"

  EM::run do
    Signal.trap('INT') { EM::stop }
    Signal.trap('TERM') { EM::stop }
    hostAndPorts.each do |serverHostAndPort|
      puts "listening on #{serverHostAndPort[:host]}:#{serverHostAndPort[:port]}"
      EM::start_server(serverHostAndPort[:host], serverHostAndPort[:port],
                       ProxyClientConnection, remoteHostAndPort)
    end
  end
end

if __FILE__ == $0
  main
end
