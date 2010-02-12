require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey" do
  before(:each) do
    @channel = Object.new
    stub(Donkey).channel { @channel }
    stub(Donkey::UUID).generate { @uuid = "uuid" }
    @donkey = Donkey.new("name")
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

  it "uses default channel" do
    @donkey.channel.should == Donkey.channel
  end

  it "calls" do
    mock(@public).call(*args = ["to","data",{"foo" => "bar"}])
    @donkey.call(*args)
  end

  it "casts" do
    mock(@public).cast(*args = ["to","data",{"foo" => "bar"}])
    @donkey.cast(*args)
  end

  it "pops a message" do
    pending
    mock(@donkey.private).pop
    @donkey.pop
  end
end

describe "Donkey::Route" do
  before(:each) do
    @channel = Object.new
    stub(Donkey).channel { @channel }
    @donkey = Donkey.new("name")
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
      msg = Object.new
      mock(msg).to { "to" }
      mock(msg).payload { "payload" }
      meta = { :foo => :bar }
      mock(msg).meta { meta }
      mock(@channel).publish("to","payload",meta.merge(:key => ""))
      @public.send(:publish,msg)
    end

    it "calls" do
      mock(@public).publish(is_a(Donkey::Message::Call))
      @public.call("to","data",:foo => :bar)
    end

    it "casts" do
      mock(@public).publish(is_a(Donkey::Message::Cast))
      @public.cast("to","data",:foo => :bar)
    end
  end

  context "Private" do
    it "delcares" do
      # FIX I don't know how not to test the implementation
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
  
  context "Call" do
    before(:each) do
      @to="name"
      @data = "data"
      @call = Donkey::Message::Call.new(@to,@data)
    end

    it "has tag" do
      @call.tag.should == "call"
    end

    it "tags data to indicate type" do
      @call.tagged_data.should be_an(Array)
      @call.tagged_data[0].should == @call.tag
      @call.tagged_data[1].should == @data
    end

    it "encodes data" do
      mock(@call).tagged_data { "tagged-data" }
      mock(BERT).encode("tagged-data") { "bert" }
      @call.payload.should == "bert"
    end

    # it "replies to donkey" do
#       pending
#       reply = @call.reply("reply")
#       reply.should 
#     end
    
  end

#   context "Cast" do
#     before(:each) do
#       @donkey = Object.new
#       @to="destination"
#       @data = "data"
#       @cast = Donkey::Message::Cast.new(@donkey,@to,@data)
#     end
#   end
end

describe "Donkey::Channel" do
  context "open" do
    it "uses default settings to initialize AMQP" do
      mock(AMQP).connect(Donkey::Channel.default_settings)
      mock(MQ).new.with_any_args
      mock(Donkey::Channel).ensure_eventmachine
      Donkey::Channel.open
    end

    it "overrides default settings to initialize AMQP" do
      mock(AMQP).connect(Donkey::Channel.default_settings.merge({ :overrided_setting => "overrided_value"}))
      mock(MQ).new.with_any_args
      Donkey::Channel.open({:overrided_setting => "overrided_value"})
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
