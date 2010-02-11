require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey" do
  before(:each) do
    AMQP.stubs(:connect)
    MQ.stubs(:new)
    @channel = stub("Channel",:direct => true).responds_like(Donkey::Channel.new)
    Donkey::Channel.stubs(:open => @channel)
    
    @name = "testing server"
    @dk = Donkey.new(@name)
    @reactor = Donkey::Reactor.new(@name)
  end

  context "react" do
    it "declares exchange" do
      @dk.channel.expects(:direct).with(@dk.name)
      @dk.react @reactor
    end
  end
  
  context "ping" do
    it "has no instance reacting" do
      @dk.ping.should == []
    end

    it "has one instance reacting" do
      @reactor.expects(:on_ping).once
      @dk.react @reactor
      @dk.ping.should have(1).pongs
    end

    it "has two instances reacting" do
      @reactor.expects(:on_ping).twice
      @dk.react @reactor
      @dk.react @reactor
      @dk.ping.should have(2).pongs
    end
  end
end

describe "Donkey::Channel" do
  before(:each) do
    # @connection = mock("Connection")
#     @channel = mock("MQ")
#     @channel.stubs(:connection => @connection)
    
    # AMQP.stubs(:connect)
#     MQ.stubs(:new)
  end

  it "creates a new AMQP channel" do
    AMQP.expects(:connect)
    MQ.expects(:new)
    #"abc".expects :foo
    Donkey::Channel.open
  end

  it "uses default settings to initialize AMQP" do
    AMQP.expects(:connect).with(Donkey::Channel.default_settings)
    MQ.expects(:new)
    #"abc".expects :foo
    Donkey::Channel.open
  end

  it "overrides default settings to initialize AMQP" do
    MQ.expects(:new)
    AMQP.expects(:connect).with(Donkey::Channel.default_settings.merge({ :overrided_setting => "overrided_value"}))
    #"abc".expects :foo
    Donkey::Channel.open({:overrided_setting => "overrided_value"})
  end
end

describe "Donkey::Reactor" do
  before(:each) do
    AMQP.stubs(:connect)
    MQ.stubs(:new)
    @name = "testing reactor"
    @donkey = Donkey.new(@name)
    @reactor = Donkey::Reactor.new(@donkey)
  end

  it "belongs to donkey" do
    @reactor.donkey == @donkey
  end

  it "has same name its donkey" do
    @reactor.name.should == @reactor.donkey.name
  end

  it "has uuid" do
    Donkey::UUID.expects(:generate).twice.returns("uuid 1","uuid 2")
    Donkey::Reactor.new(@donkey).uuid.should == "uuid 1"
    Donkey::Reactor.new(@donkey).uuid.should == "uuid 2"
  end
  
  context "on_ping" do
    before(:each) do
      @pong = @reactor.on_ping
    end

    it "returns a pong" do
      @pong.should be_a(Donkey::Pong)
    end

    it "passes name to pong" do
      @pong.name.should == @reactor.name
    end

    it "passes uuid to pong" do
      @pong.uuid.should == @reactor.uuid
    end
  end
end
