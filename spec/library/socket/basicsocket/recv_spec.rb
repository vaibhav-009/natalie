# -*- encoding: binary -*-
require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#recv" do

  before :each do
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
    ScratchPad.clear
  end

  it "receives a specified number of bytes of a message from another socket"  do
    NATFIXME 'Threads', exception: NameError, message: 'uninitialized constant Thread' do
      t = Thread.new do
        client = @server.accept
        ScratchPad.record client.recv(10)
        client.recv(1) # this recv is important
        client.close
      end
      Thread.pass while t.status and t.status != "sleep"
      t.status.should_not be_nil

      #socket = TCPSocket.new('127.0.0.1', @port) # NATFIXME: TCPSocket.new blocks
      socket = Socket.tcp('127.0.0.1', @port)
      socket.send('hello', 0)
      socket.close

      t.join
      ScratchPad.recorded.should == 'hello'
    end
  end

  platform_is_not :solaris do
    it "accepts flags to specify unusual receiving behaviour" do
      NATFIXME 'Threads', exception: NameError, message: 'uninitialized constant Thread' do
        t = Thread.new do
          client = @server.accept

          # in-band data (TCP), doesn't receive the flag.
          ScratchPad.record client.recv(10)

          # this recv is important (TODO: explain)
          client.recv(10)
          client.close
        end
        Thread.pass while t.status and t.status != "sleep"
        t.status.should_not be_nil

        #socket = TCPSocket.new('127.0.0.1', @port) # NATFIXME: TCPSocket.new blocks
        socket = Socket.tcp('127.0.0.1', @port)
        socket.send('helloU', Socket::MSG_OOB)
        socket.shutdown(1)
        t.join
        socket.close
        ScratchPad.recorded.should == 'hello'
      end
    end
  end

  it "gets lines delimited with a custom separator"  do
    NATFIXME 'Threads', exception: NameError, message: 'uninitialized constant Thread' do
      t = Thread.new do
        client = @server.accept
        ScratchPad.record client.gets("\377")

        # this call is important (TODO: explain)
        client.gets(nil)
        client.close
      end
      Thread.pass while t.status and t.status != "sleep"
      t.status.should_not be_nil

      #socket = TCPSocket.new('127.0.0.1', @port) # NATFIXME: TCPSocket.new blocks
      socket = Socket.tcp('127.0.0.1', @port)
      socket.write("firstline\377secondline\377")
      socket.close

      t.join
      ScratchPad.recorded.should == "firstline\377"
    end
  end

  it "allows an output buffer as third argument" do
    #socket = TCPSocket.new('127.0.0.1', @port) # NATFIXME: TCPSocket.new blocks
    socket = Socket.tcp('127.0.0.1', @port)
    socket.write("data")

    client = @server.accept
    buf = "foo"
    begin
      client.recv(4, 0, buf)
    ensure
      client.close
    end
    buf.should == "data"

    socket.close
  end
end

describe 'BasicSocket#recv' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :DGRAM)
      @client = Socket.new(family, :DGRAM)
    end

    after do
      @client.close
      @server.close
    end

    describe 'using an unbound socket' do
      it 'blocks the caller' do
        NATFIXME 'Implement block_caller in spec helper', exception: NoMethodError, message: "undefined method `block_caller'" do
          -> { @server.recv(4) }.should block_caller
        end
      end
    end

    describe 'using a bound socket' do
      before do
        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      describe 'without any data available' do
        it 'blocks the caller' do
          NATFIXME 'Implement block_caller in spec helper', exception: NoMethodError, message: "undefined method `block_caller'" do
            -> { @server.recv(4) }.should block_caller
          end
        end
      end

      describe 'with data available' do
        before do
          @client.connect(@server.getsockname)
        end

        it 'reads the given amount of bytes' do
          @client.write('hello')

          @server.recv(2).should == 'he'
        end

        it 'reads the given amount of bytes when it exceeds the data size' do
          @client.write('he')

          @server.recv(6).should == 'he'
        end

        it 'blocks the caller when called twice without new data being available' do
          @client.write('hello')

          @server.recv(2).should == 'he'

          NATFIXME 'Implement block_caller in spec helper', exception: NoMethodError, message: "undefined method `block_caller'" do
            -> { @server.recv(4) }.should block_caller
          end
        end

        it 'takes a peek at the data when using the MSG_PEEK flag' do
          @client.write('hello')

          @server.recv(2, Socket::MSG_PEEK).should == 'he'
          @server.recv(2).should == 'he'
        end
      end
    end
  end
end
