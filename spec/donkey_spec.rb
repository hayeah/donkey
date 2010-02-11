require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey" do
  before(:each) do
    @name = "testing server"
    @dk = Donkey.new(@name)
  end

  it "has rabbit" do
    @dk.rabbit.should be_a(Donkey::Rabbit)
  end
  
  it "creates donkey" do
  end

  context "ping" do
    before(:each) do
      @reactor = Donkey::Reactor.new(@name)
    end
    
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

describe "Donkey::Rabbit" do
  before(:each) do
    @conn = mock("Connection")
    @mq = mock("MQ")
    @mq.stubs(:connection => @conn)
    
    AMQP.stubs(:connect)
    MQ.stubs(:new)

    @rabbit = Donkey::Rabbit.new
    @rabbit.stubs(:mq => @mq)
  end

  it "has mq" do
    # pp @rb
    @rabbit.mq.should == @mq
  end
end

describe "Donkey::Reactor" do
  before(:each) do
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
