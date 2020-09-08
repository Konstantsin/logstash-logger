module LogStashLogger
  class FallbackDelivery
    attr_accessor :host, :port, :fallback_path, :logger

    def initialize(host, port, fallback_path)
      @host = host
      @port = port
      @fallback_path = fallback_path
    end

    def perform
      if ::File.size?(fallback_path).to_i > 0
        sock = Socket.tcp(host, port)
        ::File.readlines(fallback_path).each { |message| sock.puts message }
        ::File.delete(fallback_path)
      end
    rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, IOError, Errno::EPIPE => e
      Rails.logger.error(e)
    ensure
      if sock && !sock.closed?
        sock.flush
        sock.close
      end
    end
  end
end
