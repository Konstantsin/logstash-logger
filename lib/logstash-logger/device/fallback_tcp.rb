require 'openssl'
require 'logstash-logger/fallback_delivery'

module LogStashLogger
  module Device
    class FallbackTCP < TCP
      attr_accessor :fallback_path, :timeout

      def initialize(opts)
        super
        @timeout = opts.fetch(:timeout, 1)
        @fallback_path = opts.fetch(:fallback_path, 'log/logstash.development.fallback.log')
      end

      def write_batch(messages, group = nil)
        reconnect if fallback_delivery?
        # deliver_logs_from_fallback if fallback_file_not_empty? && tcp_delivery?

        io.puts "[#{messages.join(',')}]"
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, IOError, Errno::EPIPE => e
        reconnect
        retry
      end

      def tcp_io
        socket = ::Socket.tcp(@host, @port, connect_timeout: timeout)
        socket.sync = sync unless sync.nil?
        socket
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, IOError, Errno::EPIPE => e
        log_error(e)
        @io = nil
        file_io
      end

      def file_io
        @file_io = nil if !@file_io.nil? && @file_io.closed?
        @file_io ||= File.new(path: fallback_path).io
      end

      def fallback_delivery?
        !@io.nil? && @io.is_a?(::File)
      end

      def tcp_delivery?
        !@io.nil? && @io.is_a?(::Socket)
      end

      def fallback_file_not_empty?
        ::File.size?(fallback_path).to_i > 0
      end

      def deliver_logs_from_fallback
        file_io.close unless file_io.nil?

        return unless defined?(::Delayed::Job)
        return if ::Delayed::Job.where('handler LIKE ?', "%ruby/object:LogStashLogger::FallbackDelivery%").exists?

        job_id = ::Delayed::Job.enqueue(background_delivery_job).id
        error_logger.debug("job id: #{job_id}")
      end

      def background_delivery_job
        LogStashLogger::FallbackDelivery.new(host, port, fallback_path)
      end
    end
  end
end
