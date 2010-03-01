require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

def dummy_opts
  { :foo => :bar }
end

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
    @public = Object.new
    @private = Object.new
    @waiter_map = Object.new
    @ticketer = Object.new
    stub(Donkey::WaiterMap).new { @waiter_map }
    stub(Donkey::Ticketer).new { @ticketer }

    @donkey = Donkey.new("name",@reactor)
    stub(@donkey).public { @public }
    stub(@donkey).private { @private }
  end

  it "creates routes" do
    mock(Donkey::Route::Public).declare(@donkey)
    mock(Donkey::Route::Private).declare(@donkey)
    mock(@private).subscribe
    @donkey.create
  end

  it "has id" do
    @donkey.id.should == @uuid
  end

  it "has name" do
    @donkey.name.should == "name"
  end
  
  it "calls without a tag" do
    mock(@ticketer).next { "next-ticket" }
    mock(@public).call("to","data","next-ticket",{:foo => :bar})
    @donkey.call("to","data",{:foo => :bar}).should == Donkey::Receipt.new(@donkey,"next-ticket")
  end

  it "calls with a tag" do
    mock(@public).call("to","data","tag",{:foo => :bar})
    @donkey.call("to","data",{:tag => "tag", :foo => :bar}).should == Donkey::Receipt.new(@donkey,"tag")
  end
  
  it "calls and returns future" do
    pending
    mock(@public).call(*args = ["to","data"])
    f = @donkey.call!(*args)
    f.should be_a(Donkey::Future)
    # f.wait.should ==
  end

  it "casts" do
    mock(@public).cast(*args = ["to","data",{"foo" => "bar"}])
    @donkey.cast(*args)
  end

  it "replies" do
    reply_to = "reply_name#reply_id"
    mock(@header).reply_to { reply_to }
    mock(@header).message_id { "tag" }
    opts = { :foo => :bar }
    mock(@private).reply(reply_to,"result","tag",opts)
    @donkey.reply(@header,message=Object.new,"result",opts)
  end

  it "acks" do
    mock(@header).ack
    @donkey.ack(@header)
  end
  
  it "processes message" do
    mock(@reactor).process(@donkey,header="header",message="message",ack="ack")
    @donkey.process(header,message,ack)
  end

  it "has reactor" do
    @donkey.reactor.should == @reactor
  end

  it "waits receipts" do
    keys = %w(1 2 3)
    receipts = keys.map {|key|
      Donkey::Receipt.new(@donkey,key)
    }
    mock(Donkey::Waiter).new(@waiter_map,*keys)
    @donkey.wait(*receipts)
  end

  it "raises if attempting to wait for receipt from another donkey" do
    receipt = Donkey::Receipt.new(Object.new,"key")
    lambda { @donkey.wait(receipt) }.should raise_error(Donkey::BadReceipt)
  end

  it "signals ticket" do
    mock(@waiter_map).signal("key","value")
    @donkey.signal("key","value") 
  end

  it "pops with block" do
    block = mock!.entered.subject
    mock(@public).pop(dummy_opts).yields
    @donkey.pop(dummy_opts) { block.entered }
  end
  
  context "#subscribe" do
    before do
      stub(@donkey.public).subscribe
      stub(@donkey.public).unsubscribe
    end
    
    it "cannot pop if already subscribed" do
      @donkey.subscribe
      lambda { @donkey.pop }.should raise_error(Donkey::AlreadySubscribed)
    end

    it "cannot subscribe if already subscribed" do
      @donkey.subscribe
      lambda { @donkey.subscribe }.should raise_error(Donkey::AlreadySubscribed)
    end
    
    it "subscribes" do
      mock(@donkey.public).subscribe(dummy_opts)
      @donkey.subscribe(dummy_opts)
      @donkey.subscribed?.should be_true
    end

    it "unsubscribes" do
      @donkey.subscribe
      @donkey.subscribed?.should be_true
      @donkey.unsubscribe
      @donkey.subscribed?.should be_false
    end

    it "cannot unsubscribe if not subscribed" do
      lambda { @donkey.unsubscribe }.should raise_error(Donkey::NotSubscribed)
    end
  end
end

describe "Donkey::Receipt" do
  before do
    @donkey = Object.new
    @key = Object.new
    @receipt = Donkey::Receipt.new(@donkey,@key)
  end

  it "waits" do
    mock(@donkey).wait(@receipt).yields
    m = mock!.call.subject
    @receipt.wait { m.call }
  end
end

describe "Donkey::Reactor" do
  before(:each) do
    @header = Object.new
    @donkey = Object.new
  end

  def call(ack=false)
    @message = Donkey::Message::Call.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message,ack)
  end

  def cast(ack=false)
    @message = Donkey::Message::Cast.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message,ack)
  end

  def back(ack=false)
    stub(@header).message_id { "message_id" }
    @message = Donkey::Message::Back.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message,ack)
  end

  it "processes" do
    mock(Donkey::Reactor).new(donkey="donkey",header="header",message="message",ack=true) {
      mock!.process.subject
    }
    Donkey::Reactor.process(donkey,header,message,ack)
  end

  it "needs ack" do
    call(ack=true)
    @reactor.ack?.should be_true
  end

  it "doesn't need ack" do
    call(ack=false)
    @reactor.ack?.should be_false
  end

  it "acks" do
    mock(@donkey).ack(@header)
    call(ack=true)
    @reactor.ack
  end

  it "raises if no need to ack" do
    call(ack=false)
    lambda { @reactor.ack }.should raise_error(Donkey::Reactor::NoAckNeeded)
  end

  context "#reply" do
    before(:each) do
      call
      @result = "result"
      mock(@donkey).reply(@header,@message,@result,is_a(Hash))
    end
    
    it "replies" do
      @reactor.reply(@result)
    end
    
    it "raises if replied twice" do
      @reactor.reply(@result)
      lambda { @reactor.reply(@result) }.should raise_error(Donkey::Error)
    end

    it "returns true if already replied" do
      @reactor.reply(@result)
      @reactor.replied?.should == true
    end
  end
  
  context "#process" do
    it "processes Call" do
      call
      mock(@reactor).on_call
      @reactor.process
    end

    it "processes Cast" do
      cast
      mock(@reactor).on_cast
      @reactor.process
    end

    it "processes Back" do
      back
      mock(@donkey).signal(@header.message_id,@message.data)
      @reactor.process
    end

    it "handles error with on_error" do
      cast
      error = RuntimeError.new("test error")
      @reactor.def(:on_cast) do
        raise error
      end
      mock(@reactor).on_error(error)
      @reactor.process
    end

    it "dies on_error itself raises error" do
      cast
      error = RuntimeError.new("test error")
      @reactor.def(:on_cast) do
        raise error
      end
      mock(@reactor).die(error)
      @reactor.process
    end
  end

  it "dies and prints error" do
    call
    error = RuntimeError.new("error")
    mock($stderr).puts.with_any_args.twice
    mock(error).to_s
    mock(error).backtrace
    @reactor.die(error)
  end
end

describe "Donkey::Ticketer" do
  before do
    @ticketer = Donkey::Ticketer.new
  end
  
  it "produces a unique ticket" do
    # well... kinda lame way to test it.
    Set.new(10.times.map { @ticketer.next }).should have(10).tickets
  end
end

describe "Donkey::Waiter" do
  before do
    @map = Object.new
    @key1 = "key1"
    @key2 = "key2"
    @val1 = "val1"
    @val2 = "val2"
  end

  it "registers keys" do
    mock(@map).register(is_a(Donkey::Waiter),@key1,@key2)
    @waiter = Donkey::Waiter.new(@map,@key1,@key2)
  end

  def init_waiter
    stub(@map).register.with_any_args
    stub(@map).unregister.with_any_args
    @success_callback = lambda { |*args| }
    @waiter = Donkey::Waiter.new(@map,@key1,@key2,&@success_callback)
  end
  
  context "#signal" do
    before do
      init_waiter
    end

    def signal1
      @waiter.signal(@key1,@val1)
    end

    def signal2
      @waiter.signal(@key2,@val2)
    end
    
    it "is not ready until all its registered keys are signaled" do
      signal1
      @waiter.ready?.should == false
      signal2
      @waiter.ready?.should == true
    end

    it "checks if value has been received" do
      @waiter.received?(@key1).should == false
      signal1
      @waiter.received?(@key1).should == true
    end

    it "gets received value" do
      signal1
      signal2
      @waiter.value(@key1).should == @val1
      @waiter.value(@key2).should == @val2
    end

    it "raises if trying to get value not received" do
      lambda { @waiter.value(@key1) }.should raise_error(Donkey::Waiter::NotReceived)
    end

    it "associate signaled keys with signaled values" do
      signal1
      @waiter.received[@key1]
    end

    it "calls on_success if all signals had arrived" do
      mock(@waiter).on_success
      signal1; signal2
    end

    it "get all received values in order" do
      signal1; signal2
      @waiter.values.should == [@val1,@val2]
    end

    it "raises error if key is signaled twice" do
      signal1
      lambda { signal1 }.should raise_error(Donkey::Waiter::AlreadySignaled)
    end
  end

  context "#on_success" do
    before do
      init_waiter
      @values = [1,2,3]
      stub(@waiter).values { @values }
    end

    def success
      @waiter.send(:on_success)
    end
    
    it "unregisters itself" do
      mock(@map).unregister(@waiter,@key1,@key2)
      success
    end

    it "completes" do
      @waiter.done?.should == false
      @waiter.success?.should == false
      success
      @waiter.done?.should == true
      @waiter.success?.should == true
    end

    it "calls success callback" do
      mock(@waiter).success_callback { mock!.call(*@values).subject }
      success
    end

    it "does nothing if waiter is already done" do
      mock(@waiter).done? { true }
      success
      @waiter.success?.should == false
    end
  end

  context "#timeout" do

    before do
      init_waiter
      @timeout = 10
      @timeout_callback = lambda { |*args| }
      @timer = Object.new
      stub(EM).add_timer{ @timer }.with_any_args
      stub(@waiter).on_timeout
    end
    
    def set_timeout
      @waiter.timeout(@timeout,&@timeout_callback)
    end

    it "raises error if timeout already set" do
      set_timeout
      lambda { set_timeout }.should raise_error(Donkey::Waiter::TimeoutAlreadySet)
    end

    it "returns waiter instance" do
      set_timeout.should == @waiter
    end

    it "sets timeout timer" do
      a_timer = Object.new
      mock(@waiter).on_timeout
      mock(EM::Timer).new(@timeout) { a_timer }.yields
      set_timeout
      @waiter.timer.should == a_timer
    end
    
    it "sets timeout callback" do
      set_timeout
      @waiter.timeout_callback.should == @timeout_callback
    end
  end
  
  context "#on_timeout" do
    before do
      init_waiter
      stub(@waiter).timeout_callback { lambda {}}
    end
    
    def timeout
      @waiter.send(:on_timeout)
    end
    
    it "does nothing if waiter is already done" do
      mock(@waiter).done? { true }
      timeout
      @waiter.timeout?.should == false
    end

    it "completes" do
      @waiter.done?.should == false
      @waiter.timeout?.should == false
      timeout
      @waiter.done?.should == true
      @waiter.timeout?.should == true
    end

    it "calls timeout block" do
      mock(@waiter).timeout_callback { mock!.call(@waiter).subject }
      timeout
    end

    it "unregisters itself" do
      mock(@map).unregister(@waiter,@key1,@key2)
      timeout
    end
  end

  context "states" do
    before { init_waiter }
    it "is success if status is :success" do
      mock(@waiter).status { :success }
      @waiter.success?.should == true
    end

    it "is timeout if status is :timeout" do
      mock(@waiter).status { :timeout }
      @waiter.timeout?.should == true
    end
  end
  
  context "#complete" do
    before do
      init_waiter
      @complete_block = lambda { }
    end

    def complete
      @waiter.send(:complete,:status,&@complete_block)
    end

    it "sets status" do
      complete
      @waiter.status.should == :status
    end

    it "sets done" do
      complete
      @waiter.done?.should == true
    end

    it "calls completion block" do
      # ruby 1.8.7_174 bug breaks mocking the #call method of a block
      # mock(@complete_block).call
      ## so we put the expectation inside
      mock = mock!.call.subject
      @complete_block = lambda { mock.call }
      complete
    end

    it "does nothing if already completed" do
      @complete_block = lambda { raise "don't call" }
      mock(@waiter).done? { true }
      complete
    end

    it "cancels timeout timer if there's one" do
      timer = mock!.cancel.subject
      stub(@waiter).timer { timer }
      complete
    end
  end
  
end

describe "Donkey::WaiterMap" do
  before(:each) do
    @map = Donkey::WaiterMap.new
    @waiter1 = Object.new
    @waiter2 = Object.new
    @key1 = "key1"
    @key2 = "key2"
  end

  it "registers waiters" do
    @map.register(@waiter1,@key1)
    @map.waiters_of(@key1).should include(@waiter1)
    @map.register(@waiter2,@key2)
    @map.waiters_of(@key2).should include(@waiter2)
  end

  it "returns all waiters for a key" do
    @map.register(@waiter1,@key1)
    @map.register(@waiter2,@key1,@key2)
    s = @map.waiters_of(@key1)
    s.should include(@waiter1,@waiter2)
    s.should have(2).waiters
    s = @map.waiters_of(@key2)
    s.should include(@waiter2)
    s.should have(1).waiter
  end

  it "unregisters waiters under a key" do
    @map.register(@waiter1,@key1,@key2)
    @map.unregister(@waiter1,@key1)
    @map.waiters_of(@key1).should be_empty
    @map.waiters_of(@key2).should include(@waiter1)
  end

  it "deletes key if no more waiters are under that key" do
    @map.register(@waiter1,@key1)
    @map.map.should have(1).key
    @map.unregister(@waiter1,@key1)
    @map.map.should have(0).keys
  end

  it "does nothing unregistering an unregistered waiter" do
    @map.unregister(@waiter1,@key1,@key2)
  end

  it "signals waiters" do
    @map.register(@waiter1,@key1)
    @map.register(@waiter2,@key1,@key2)
    mock(@waiter1).signal(@key1,1)
    mock(@waiter2).signal(@key1,1).then.signal(@key2,2)
    @map.signal(@key1,1)
    @map.signal(@key2,2)
  end
end

describe "Donkey::Route" do
  before(:each) do
    @channel = Object.new
    @donkey = Donkey.new("name",@reactor=Object.new,@channel)
  end

  context "Route" do
    before(:each) do
      @exchange = Object.new
      @queue = Object.new
      @route = Donkey::Route.new(@donkey)
      stub(@route).queue { @queue }
      stub(@route).exchange { @exchange }
      @header = Object.new
      @payload = Object.new
    end

    def ack_opts
      dummy_opts.merge(:ack => true)
    end

    it "subscribes" do
      mock(@queue).subscribe(dummy_opts).yields(@header,@payload)
      mock(@route).process(@header,@payload,false)
      @route.subscribe(dummy_opts)
    end

    it "subscribes with ack" do
      mock(@queue).subscribe(ack_opts).yields(@header,@payload)
      mock(@route).process(@header,@payload,true)
      @route.subscribe(ack_opts)
    end

    it "unsubscribes" do
      mock(@queue).unsubscribe(dummy_opts)
      @route.unsubscribe(dummy_opts)
    end

    it "pops a message" do
      mock(@queue).pop(dummy_opts).yields(@header,@payload)
      mock(@route).process(@header,@payload,false)
      @route.pop(dummy_opts)
    end

    it "pops a message with ack" do
      mock(@queue).pop(ack_opts).yields(@header,@payload)
      mock(@route).process(@header,@payload,true)
      @route.pop(ack_opts)
    end

    it "handles empty queue when popping" do
      mock(@queue).pop(dummy_opts).yields(nil,nil)
      dont_allow(@route).process
      block = mock!.entered.subject
      @route.pop(dummy_opts) { block.entered  }
    end
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
      mock(@channel).publish("to","payload",opts)
      @public.send(:publish,"to",msg,opts)
    end

    it "calls" do
      tag="tag"
      mock(@public).publish("to",is_a(Donkey::Message::Call),
                            { :foo => :bar,
                              :reply_to => "#{@donkey.name}##{@donkey.id}",
                              :message_id => tag})
      @public.call("to","data",tag,:foo => :bar)
    end

    it "casts" do
      mock(@public).publish("to",is_a(Donkey::Message::Cast),:foo => :bar)
      @public.cast("to","data",:foo => :bar)
    end

    it "processes" do
      mock(Donkey::Message).decode("payload") { "message" }
      mock(@donkey).process("header","message","ack")
      @public.send(:process,"header","payload","ack")
    end
  end

  context "Private" do
    before(:each) do
      mock(@channel).direct(@donkey.name)
      mock(@channel).queue(@donkey.id,:auto_delete => true) {
        mock!.bind(@donkey.name,:key => @donkey.id).subject
      }
      @private = Donkey::Route::Private.declare(@donkey)
    end

    it "declares" do
      
    end

    it "replies" do
      data="data"
      mock(Donkey::Message::Back).new("data") { "back-message" }
      mock(@private).publish("to","back-message",
                             {:foo => :bar, :routing_key => "id", :message_id => "tag"})
      @private.reply("to#id","data","tag",{ :foo => :bar })
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
