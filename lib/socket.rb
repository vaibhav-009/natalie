require 'natalie/inline'
require 'socket.cpp'

class SocketError < StandardError
end

class BasicSocket < IO
  __bind_method__ :getsockname, :BasicSocket_getsockname
  __bind_method__ :getsockopt, :BasicSocket_getsockopt
  __bind_method__ :local_address, :BasicSocket_local_address
  __bind_method__ :recv, :BasicSocket_recv
  __bind_method__ :send, :BasicSocket_send
  __bind_method__ :setsockopt, :BasicSocket_setsockopt

  attr_writer :do_not_reverse_lookup

  def do_not_reverse_lookup
    if @do_not_reverse_lookup.nil?
      self.class.do_not_reverse_lookup
    else
      @do_not_reverse_lookup
    end
  end

  class << self
    __bind_method__ :for_fd, :BasicSocket_s_for_fd

    def do_not_reverse_lookup
      case @do_not_reverse_lookup
      when nil
        true
      when false
        false
      else
        true
      end
    end

    def do_not_reverse_lookup=(do_not)
      case do_not
      when false, nil
        @do_not_reverse_lookup = false
      else
        @do_not_reverse_lookup = true
      end
    end
  end

  def connect_address
    local_address
  end
end

class IPSocket < BasicSocket
  __bind_method__ :addr, :IPSocket_addr
end

class TCPSocket < IPSocket
  __bind_method__ :initialize, :TCPSocket_initialize
end

class TCPServer < TCPSocket
  __bind_method__ :initialize, :TCPServer_initialize
  __bind_method__ :accept, :TCPServer_accept
end

require_relative './socket/constants'

class Socket < BasicSocket
  Constants.constants.each do |name|
    const_set(name, Constants.const_get(name))
  end

  SHORT_CONSTANTS = {
    DGRAM: SOCK_DGRAM,
    INET: AF_INET,
    INET6: AF_INET6,
    IP: IPPROTO_IP,
    KEEPALIVE: SO_KEEPALIVE,
    LINGER: SO_LINGER,
    OOBINLINE: SO_OOBINLINE,
    REUSEADDR: SO_REUSEADDR,
    SOCKET: SOL_SOCKET,
    STREAM: SOCK_STREAM,
    TTL: IP_TTL,
    TYPE: SO_TYPE,
  }.freeze

  class Option
    def initialize(family, level, optname, data)
      @family = Socket.const_name_to_i(family)
      @level = Socket.const_name_to_i(level)
      @optname = Socket.const_name_to_i(optname)
      @data = data
    end

    attr_reader :family, :level, :optname, :data

    alias to_s data

    class << self
      def bool(family, level, optname, data)
        Option.new(family, level, optname, [data ? 1 : 0].pack('i'))
      end

      def int(family, level, optname, data)
        Option.new(family, level, optname, [data].pack('i'))
      end

      __bind_method__ :linger, :Socket_Option_s_linger
    end

    __bind_method__ :bool, :Socket_Option_bool
    __bind_method__ :int, :Socket_Option_int
    __bind_method__ :linger, :Socket_Option_linger
  end

  __bind_method__ :initialize, :Socket_initialize

  __bind_method__ :accept, :Socket_accept
  __bind_method__ :bind, :Socket_bind
  __bind_method__ :close, :Socket_close
  __bind_method__ :closed?, :Socket_is_closed
  __bind_method__ :connect, :Socket_connect
  __bind_method__ :listen, :Socket_listen

  class << self
    __bind_method__ :pack_sockaddr_in, :Socket_pack_sockaddr_in
    __bind_method__ :pack_sockaddr_un, :Socket_pack_sockaddr_un
    __bind_method__ :unpack_sockaddr_in, :Socket_unpack_sockaddr_in
    __bind_method__ :unpack_sockaddr_un, :Socket_unpack_sockaddr_un

    __bind_method__ :getaddrinfo, :Socket_s_getaddrinfo

    __bind_method__ :const_name_to_i, :Socket_const_name_to_i

    alias sockaddr_in pack_sockaddr_in
    alias sockaddr_un pack_sockaddr_un

    def tcp(host, port, local_host = nil, local_port = nil)
      block_given = block_given?
      Socket.new(:INET, :STREAM).tap do |socket|
        if local_host || local_port
          local_sockaddr = Socket.pack_sockaddr_in(
            local_port || host,
            local_host || port,
          )
          socket.bind(local_sockaddr)
        end
        sockaddr = Socket.pack_sockaddr_in(port, host)
        socket.connect(sockaddr)
        if block_given
          begin
            yield socket
          ensure
            socket.close
          end
        end
      end
    end
  end
end

class Addrinfo
  attr_reader :afamily, :family, :pfamily, :protocol, :socktype, :unix_path

  class << self
    def ip(ip)
      Addrinfo.new(Socket.pack_sockaddr_in(0, ip), nil, nil, Socket::IPPROTO_IP)
    end

    def tcp(ip, port)
      Addrinfo.new(Socket.pack_sockaddr_in(port, ip), nil, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
    end

    def udp(ip, port)
      Addrinfo.new(Socket.pack_sockaddr_in(port, ip), nil, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP)
    end

    def unix(path)
      Addrinfo.new(Socket.pack_sockaddr_un(path))
    end
  end

  __bind_method__ :initialize, :Addrinfo_initialize
  __bind_method__ :to_sockaddr, :Addrinfo_to_sockaddr

  def ip_address
    unless @ip_address
      raise SocketError, 'need IPv4 or IPv6 address'
    end
    @ip_address
  end

  def ip_port
    unless @ip_port
      raise SocketError, 'need IPv4 or IPv6 address'
    end
    @ip_port
  end
end
