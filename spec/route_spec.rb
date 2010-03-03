require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Route" do
  before(:each) do
    @channel = Object.new
    stub(Donkey).channel { @channel }
    @donkey = Donkey.new("name",@reactor=Object.new)
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

  context "Topic" do
    before do
      stub(@channel).queue.with_any_args
      @topic = Donkey::Route::Topic.new(@donkey)
    end

    it "creates topic exchange" do
      pending
      mock(@channel).topic("name",dummy_opts)
      @topic.topic("name",dummy_opts)
    end
    
    it "declares" do
      mock(@channel).queue("queue_name")
      mock(@topic).queue_name { "queue_name" }
      @topic.declare
    end

    it "listens" do
      mock(@topic).queue { mock!.bind("exchange", :routing_key => "topic-key")}
      @topic.listen("exchange","topic-key")
    end

    it "unlistens" do
      mock(@topic).queue { mock!.unbind("exchange", :routing_key => "topic-key")}
      @topic.unlisten("exchange","topic-key")
    end

    it "publishes event" do
      mock(Donkey::Message::Event).new("data") { "event-message" }
      mock(@topic).publish("name","event-message",dummy_opts.merge(:routing_key => "key"))
      @topic.event("name","key","data",dummy_opts)
    end
  end
end