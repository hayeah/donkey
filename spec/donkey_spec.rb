require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey" do
  it "uses default channel" do
    stub(Donkey).default_channel { "default channel" }
    Donkey.new("test","reactor").channel.should == Donkey.default_channel
  end

  it "uses current channel" do
    stub(Donkey).channel { "current channel" }
    Donkey.new("test","reactor").channel.should == Donkey.channel
  end

  context ".with" do
    class FakeChannel < Donkey::Channel
      def initialize
      end
    end
    before(:each) do
      @channel = FakeChannel.new
      @default_channel = Object.new
      stub(Donkey).default_channel { @default_channel }
    end
    it "opens a channel for block context" do
      opts = { :foo => 1 }
      @channel = Object.new
      mock(Donkey::Channel).open(opts) { @channel }
      Donkey.with(opts) {
        Donkey.channel.should == @channel
      }
    end

    it "uses opened channel for block context" do
      Donkey.with(@channel) {
        Donkey.channel.should == @channel
      }
    end

    it "restores context outside block context" do
      Donkey.with(@channel) {
        Donkey.channel.should == @channel
      }
      Donkey.channel.should == Donkey.default_channel
    end
  end
end

describe "Donkey" do
  before(:each) do
    @channel = Object.new
    stub(Donkey).default_channel { @channel }
    stub(Donkey::UUID).generate { @uuid = "uuid" }
    @reactor = Object.new
    @donkey = Donkey.new("name",@reactor)
    @public = Object.new
    @private = Object.new
    stub(@donkey).public { @public }
    stub(@donkey).private { @private }
  end

  it "creates routes" do
    mock(Donkey::Route::Public).declare(@donkey)
    mock(Donkey::Route::Private).declare(@donkey)
    @donkey.create
  end

  it "has id" do
    @donkey.id.should == @uuid
  end

  it "has name" do
    @donkey.name.should == "name"
  end
  
  it "calls" do
    pending
    mock(@public).call(*args = ["to","data",{"foo" => "bar"}])
    @donkey.call(*args)
  end

  it "calls and returns future" do
    pending
    mock(@public).call(*args = ["to","data"])
    f = @donkey.call!(*args)
    f.should be_a(Donkey::Future)
    f.wait.should ==
  end

  it "casts" do
    mock(@public).cast(*args = ["to","data",{"foo" => "bar"}])
    @donkey.cast(*args)
  end

  it "processes message" do
    mock(@reactor).process(@donkey,header="header",message="message")
    @donkey.process(header,message)
  end

  it "has reactor" do
    @donkey.reactor.should == @reactor
  end
end

describe "Donkey::Reactor" do
  before(:each) do
    @header = Object.new
    @donkey = Object.new
  end

  def call
    @message = Donkey::Message::Call.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message)
  end

  def cast
    @message = Donkey::Message::Cast.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message)
  end

  it "processes" do
    mock(Donkey::Reactor).new(donkey="donkey",header="header",message="message") { mock!.process.subject }
    Donkey::Reactor.process(donkey,header,message)
  end
  
  context "#on_message" do
    it "reacts to call" do
      call
      mock(@reactor).on_call
      @reactor.process
    end

    it "reacts to cast" do
      cast
      mock(@reactor).on_cast
      @reactor.process
    end

    it "handles error with on_error" do
      cast
      error = Class.new(RuntimeError).new("test error")
      # welp... there's probably a better way to test this
      class << @reactor; self end.instance_eval do
        define_method(:on_cast) do
          raise error
        end
      end
      mock(@reactor).on_error(error)
      @reactor.process
    end
  end

  it "discards" do
    lambda { @reactor}
  end
end

describe "Donkey::Route" do
  before(:each) do
    @channel = Object.new
    @donkey = Donkey.new("name",@reactor=Object.new,@channel)
  end

  context "Public" do
    before(:each) do
      @exchange = Object.new
      @queue = Object.new
      mock(@channel).direct(@donkey.name) { @exchange }
      mock(@channel).queue(@donkey.name) { mock!.bind(@donkey.name,:key => ""){ @queue }.subject }
      @public = Donkey::Route::Public.declare(@donkey)
    end
    
    it "declares" do
      @public.queue.should == @queue
      @public.exchange.should == @exchange
    end

    it "publishes" do
      mock(msg = Object.new).encode { "payload" }
      opts = { :foo => :bar }
      mock(@channel).publish("to","payload",opts.merge(:key => ""))
      @public.send(:publish,"to",msg,opts)
    end

    it "calls" do
      mock(@public).publish("to",is_a(Donkey::Message::Call),:foo => :bar)
      @public.call("to","data",:foo => :bar)
    end

    it "casts" do
      mock(@public).publish("to",is_a(Donkey::Message::Cast),:foo => :bar)
      @public.cast("to","data",:foo => :bar)
    end

    it "pops a message" do
      header = "header"
      payload = "payload"
      queue = Object.new
      class << queue
        attr_reader :captured_block
        def pop(opts,&block)
          @captured_block = block
        end
      end
      # mock the object we are testing to return the queue double
      mock(@public).queue { queue }
      mock(@public).process(header,payload)
      
      @public.pop
      # test the call back
      queue.captured_block.call(header,payload)
    end

    it "processes" do
      mock(Donkey::Message).decode("payload") { "message" }
      mock(@donkey).process("header","message")
      @public.send(:process,"header","payload")
    end
  end

  context "Private" do
    it "delcares" do
      mock(@channel).direct(@donkey.name)
      mock(@channel).queue(@donkey.id,:auto_delete => true) { mock!.bind(@donkey.name,:key => @donkey.id).subject }
      r = Donkey::Route::Private.declare(@donkey)
    end

    it "publishes" do
      
    end
  end
end

describe "Donkey::Message" do
  it "raises if a class has no associated tag" do
    new_message_class = Class.new(Donkey::Message)
    lambda { new_message_class.tag }.should raise_error
  end

  it "raises if a tag has no associated class" do
    lambda { Donkey::Message.tag_to_class("fwajelkfjlfla") }.should raise_error
  end

  context ".decode" do
    it "raises DecodeError on bad payload" do
      lambda { Donkey::Message.decode("junk data") }.should raise_error(Donkey::Message::DecodeError)
    end
  end

  context "Message" do
    before(:each) do
      msg_klass = Class.new(Donkey::Message)
      stub(msg_klass).tag { "test_tag" }
      @msg = msg_klass.new("data")
    end

    it "tags data to indicate type" do
      @msg.tagged_data.should be_an(Array)
      @msg.tagged_data[0].should == "test_tag"
      @msg.tagged_data[1].should == "data"
    end

    it "encodes data" do
      mock(@msg).tagged_data { "tagged-data" }
      mock(BERT).encode("tagged-data") { "bert" }
      @msg.encode.should == "bert"
    end
  end
  
  
  context "Call" do
    before(:each) do
      @call = Donkey::Message::Call.new(@data = "data")
    end

    it "has tag" do
      @call.tag.should == "call"
    end
  end

  context "Cast" do
    before(:each) do
      @msg = Donkey::Message::Cast.new(@data="data")
    end

    it "has tag" do
      @msg.tag.should == "cast"
    end
  end
end

describe "Donkey::Channel" do
  context "open" do
    before(:each) do
      connection = Object.new
      mock(connection).connection_status
      mock(Donkey::Channel).ensure_eventmachine
      mock(AMQP).connect(is_a(Hash)) { connection }
      mock(MQ).new(connection)
    end
    
    it "uses default settings to initialize AMQP" do
      c = Donkey::Channel.open
      c.settings.should == Donkey::Channel.default_settings
    end

    it "overrides default settings to initialize AMQP" do
      c = Donkey::Channel.open(:foo => 10)
      c.settings.should == Donkey::Channel.default_settings.merge(:foo => 10)
    end
  end

  # FIXME dunno how to test this
  # context "ensure eventmachine" do
#     it "starts if not running" do
#       stub(EM).reactor_running? { false }
#       mock(EM).run
#       mock(Thread).new
#       Donkey::Channel.ensure_eventmachine
#     end

#     it "does nothing if already running" do
#       stub(EM).reactor_running? { true }
#       dont_allow(EM).run
#       dont_allow(Thread).new
#       Donkey::Channel.ensure_eventmachine
#     end
#   end
  
end
