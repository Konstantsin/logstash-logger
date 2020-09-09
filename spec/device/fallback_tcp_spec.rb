require 'logstash-logger'

describe LogStashLogger::Device::FallbackTCP do
  include_context 'device'

  let(:fallback_path) { `pwd` + '/logstash.fallback.log' }
  let(:fallback_tcp_device) do
    LogStashLogger::Device.new(
      type: :fallback_tcp,
      port: port,
      fallback_path: fallback_path,
      error_logger: Logger.new(IO::NULL),
      sync: true)
  end

  context "when server unavailable" do
    before do
      allow(fallback_tcp_device.error_logger).to receive(:error)
      allow(fallback_tcp_device.error_logger).to receive(:warn)
      allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_raise(Errno::ETIMEDOUT)
    end

    it "returns file io as fallback" do
      expect(fallback_tcp_device.io).to be_a(::File)
    end

    it "has marked as fallback delivery" do
      fallback_tcp_device.connect
      expect(fallback_tcp_device).to be_fallback_delivery
    end

    it 'has io with :fallback_path option' do
      expect(fallback_tcp_device.io.path).to include('/logstash.fallback.log')
    end
  end

  describe '#write_batch' do
    let(:tcp_socket) { instance_double(IO) }

    before do
      allow(tcp_socket).to receive(:sync=)
      allow(fallback_tcp_device).to receive(:deliver_logs_from_fallback)
      allow(fallback_tcp_device).to receive(:fallback_file_not_empty?).and_return(true)
    end

    context 'when server appears online' do
      before do
        allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_raise(Errno::ETIMEDOUT)
        allow(tcp_socket).to receive(:puts)
      end

      it 'switches from file to tcp' do
        expect(fallback_tcp_device.io).to be_a(File)
        fallback_tcp_device.write_batch(['message'])
        allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_return(tcp_socket)
        fallback_tcp_device.write_batch(['message'])
        expect(fallback_tcp_device.io).to eq(tcp_socket)
      end

      xit 'delivers data from log file' do
        allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_return(tcp_socket)
        fallback_tcp_device.write_batch(['message'])
        expect(fallback_tcp_device).to have_received(:deliver_logs_from_fallback)
      end
    end

    context 'when server goes offline' do
      before do
        allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_return(tcp_socket)
        allow(tcp_socket).to receive(:puts)
      end

      it 'switches from file to tcp' do
        fallback_tcp_device.write_batch(['message'])
        expect(fallback_tcp_device.io).to eq(tcp_socket)
        allow(tcp_socket).to receive(:puts).and_raise(Errno::EPIPE)
        allow(::Socket).to receive(:tcp).with(HOST, port, connect_timeout: 1).and_raise(Errno::ETIMEDOUT)
        allow(tcp_socket).to receive(:closed?).and_return(true)
        allow(tcp_socket).to receive(:close)
        fallback_tcp_device.with_connection do
          fallback_tcp_device.write_batch(['message'])
        end
        expect(fallback_tcp_device.io).to be_a(File)
      end
    end
  end
end
