#!/usr/bin/env ruby

require 'eventmachine'
require 'socket'

class ProxyRemoteConnection < EM::Connection

  def initialize(clientConnection)
    super()
    @proxyClientConnection = clientConnection
    @localHostAndPortString = ''
    @remoteHostAndPortString = ''
  end

  def connection_completed
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    @localHostAndPortString = "#{localIP}:#{localPort}"
    remotePort, remoteIP = Socket.unpack_sockaddr_in(get_peername)
    @remoteHostAndPortString = "#{remoteIP}:#{remotePort}"
    puts "connect complete #{@localHostAndPortString} -> " +
         "#{@remoteHostAndPortString}"

    EM::enable_proxy(self, @proxyClientConnection)
    @proxyClientConnection.start_proxy_to_remote
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    if not @remoteHostAndPortString.empty?
      puts "close #{@localHostAndPortString} -> #{@remoteHostAndPortString}"
    end
    @proxyClientConnection.close_connection
  end

end

class ProxyClientConnection < EM::Connection

  def initialize(remoteHostAndPort)
    super()
    @remoteHostAndPort = remoteHostAndPort
    @clientHostAndPortString = ''
    @localHostAndPortString = ''
  end

  def post_init
    clientPort, clientIP = Socket.unpack_sockaddr_in(get_peername)
    @clientHostAndPortString = "#{clientIP}:#{clientPort}"
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    @localHostAndPortString = "#{localIP}:#{localPort}"
    puts "accept #{@clientHostAndPortString} -> #{@localHostAndPortString}"

    pause
    @proxyRemoteConnection =
      EM::connect(@remoteHostAndPort[:host], @remoteHostAndPort[:port],
                  ProxyRemoteConnection, self)
  end

  def start_proxy_to_remote
    resume
    EM::enable_proxy(self, @proxyRemoteConnection)
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    puts "close #{@clientHostAndPortString} -> #{@localHostAndPortString}"
    @proxyRemoteConnection.close_connection
  end

end

def main
  hostAndPorts = []
  hostPortRE = /^(.+):(\d+)$/
  ARGV.each do |arg|
    match = hostPortRE.match(arg)
    if match.nil?
      raise "Illegal argument #{arg}"
    else
      hostAndPorts << { :host => match[1], :port => match[2].to_i }
    end
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
    hostAndPorts.each do |hostAndPort|
      host = hostAndPort[:host]
      port = hostAndPort[:port]
      puts "listening on #{host}:#{port}"
      EM::start_server(host, port, ProxyClientConnection, remoteHostAndPort)
    end
  end
end

if __FILE__ == $0
  main
end
