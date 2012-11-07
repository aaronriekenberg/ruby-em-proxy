#!/usr/bin/env ruby

require 'eventmachine'
require 'logger'
require 'socket'

LOGGER = Logger.new(STDOUT)
LOGGER.formatter = proc do |severity, datetime, progname, msg|
  formattedDateTime = datetime.strftime("%Y-%m-%d %H:%M:%S.") << 
                      ("%06d" % datetime.usec)
  "#{formattedDateTime} #{msg}\n"
end

class ProxyRemoteConnection < EM::Connection

  def initialize(connectComplete, connectFailed)
    super()
    @connectComplete = connectComplete
    @connectFailed = connectFailed
  end

  def connection_completed
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    remotePort, remoteIP = Socket.unpack_sockaddr_in(get_peername)
    @connectionString =
      "#{localIP}:#{localPort} -> #{remoteIP}:#{remotePort}"
    LOGGER.info("connected #{@connectionString}")

    @connectFailed = nil
    @connectComplete.call(self) if @connectComplete
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    LOGGER.info("close #{@connectionString}") if @connectionString
    @connectFailed.call if @connectFailed
  end

end

class ProxyClientConnection < EM::Connection

  def initialize(remoteHostAndPort)
    super()
    @remoteHostAndPort = remoteHostAndPort
  end

  def post_init
    clientPort, clientIP = Socket.unpack_sockaddr_in(get_peername)
    localPort, localIP = Socket.unpack_sockaddr_in(get_sockname)
    @connectionString =
      "#{clientIP}:#{clientPort} -> #{localIP}:#{localPort}"
    LOGGER.info("accept #{@connectionString}")

    pause
    connectComplete = proc { |remoteConnection| start_proxy(remoteConnection) }
    connectFailed = proc { close_connection }
    EM::connect(@remoteHostAndPort[:host], @remoteHostAndPort[:port],
                ProxyRemoteConnection,
                connectComplete, connectFailed)
  end

  def start_proxy(remoteConnection)
    resume
    EM::enable_proxy(self, remoteConnection, 65536)
    EM::enable_proxy(remoteConnection, self, 65536)
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    LOGGER.info("close #{@connectionString}") if @connectionString
  end

end

def main
  hostPortRE = /^(.+):(\d+)$/
  hostAndPorts = ARGV.map do |arg|
    match = hostPortRE.match(arg)
    raise "Illegal argument '#{arg}'" if match.nil?
    { :host => match[1], :port => match[2].to_i }
  end

  if hostAndPorts.length < 2
    LOGGER.warn("Usage: #{$0} <listen addr> [ <listen addr> ... ] <remote addr>")
    exit(1)
  end

  remoteHostAndPort = hostAndPorts.pop
  LOGGER.info("remote address #{remoteHostAndPort[:host]}:#{remoteHostAndPort[:port]}")

  EM::run do
    Signal.trap('INT') { EM::stop }
    Signal.trap('TERM') { EM::stop }
    hostAndPorts.each do |serverHostAndPort|
      LOGGER.info("listening on #{serverHostAndPort[:host]}:#{serverHostAndPort[:port]}")
      EM::start_server(serverHostAndPort[:host], serverHostAndPort[:port],
                       ProxyClientConnection, remoteHostAndPort)
    end
  end
end

if __FILE__ == $0
  main
end
