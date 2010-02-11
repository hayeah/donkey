require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey" do
  before(:each) do
    stub(AMQP).connect.with_any_args
    stub(MQ).new.with_any_args
    @channel = Donkey::Channel.open
    stub(Donkey::Channel).open { @channel }

    @name = "testing server"
    @donkey = Donkey.new(@name)
    @reactor = Donkey::Reactor.new(@name)
  end

  it "has name" do
    @donkey.name.should == @name
  end
  
  # it "declares exchange" do
#     mock(@channel).direct(@donkey.name)
#     @donkey.exchange
#     @donkey.
#   end

#   it "sets exchange once only" do
#     mock(@channel).direct(@donkey.name).once
#     @donkey.exchange
#     @donkey.exchange
#   end
  
  context "react" do
    
  end
  
  context "ping" do
    it "has no instance reacting" do
      @donkey.ping.should == []
    end

    it "sends ping into rabbitmq" do
      mock(@channel).publish(is_a(Donkey::Ping)).once
      @donkey.ping
    end

    it "has one instance reacting" do
      mock(@reactor).on_ping.once
      @donkey.react @reactor
      @donkey.ping.should have(1).pongs
    end

    it "has two instances reacting" do
      mock(@reactor).on_ping.twice
      @donkey.react @reactor
      @donkey.react @reactor
      @donkey.ping.should have(2).pongs
    end
  end
end

describe "Donkey::Channel" do
  before(:each) do
    @_amqp = mock(AMQP).connect(is_a(Hash))
    @_mq = mock(MQ).new.with_any_args
  end

  it "creates a new AMQP channel" do
    Donkey::Channel.open
  end

  it "uses default settings to initialize AMQP" do
    @_amqp.with(Donkey::Channel.default_settings)
    Donkey::Channel.open
  end

  it "overrides default settings to initialize AMQP" do
    @_amqp.with(Donkey::Channel.default_settings.merge({ :overrided_setting => "overrided_value"}))
    Donkey::Channel.open({:overrided_setting => "overrided_value"})
  end
end

describe "Donkey::Reactor" do
  before(:each) do
    stub(AMQP).connect
    stub(MQ).new
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
    guids = ["uuid 1","uuid 2"]
    mock(Donkey::UUID).generate.twice { guids.shift }
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
