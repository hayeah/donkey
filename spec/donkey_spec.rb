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
    @public = Object.new
    @private = Object.new
    @topic = Object.new
    @fanout = Object.new
    @signal_map = Object.new
    @ticketer = Object.new
    stub(Donkey::SignalMap).new { @signal_map }
    stub(Donkey::Ticketer).new { @ticketer }

    @donkey = Donkey.new("name",@reactor)
    stub(@donkey).public { @public }
    stub(@donkey).private { @private }
    stub(@donkey).topic { @topic }
    stub(@donkey).fanout { @fanout }
  end

  it "creates routes" do
    mock(Donkey::Route::Public).declare(@donkey)
    mock(Donkey::Route::Private).declare(@donkey)
    mock(Donkey::Route::Topic).declare(@donkey)
    mock(Donkey::Route::Fanout).declare(@donkey)
    @donkey.create
  end

  it "has id" do
    @donkey.id.should == @uuid
  end

  it "has name" do
    @donkey.name.should == "name"
  end

  it "casts" do
    mock(@public).cast(*args = ["to","data",{"foo" => "bar"}])
    @donkey.cast(*args)
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

  it "signals ticket" do
    mock(@signal_map).signal("key","value")
    @donkey.signal("key","value") 
  end

  context "#wait" do
    before do
      @keys = %w(1 2 3)
      @receipts = @keys.map {|key|
        Donkey::Receipt.new(@donkey,key)
      }
    end
    
    it "waits receipts" do
      mock(Donkey::Waiter).new(@signal_map,*@keys).yields
      here = mock!.call.subject
      @donkey.wait(*@receipts) { here.call }
    end

    it "raises if attempting to wait for receipt from another donkey" do
      receipt = Donkey::Receipt.new(Object.new,"key")
      lambda { @donkey.wait(receipt) { } }.should raise_error(Donkey::BadReceipt)
    end
    
    it "raises if block not given" do
      lambda { @donkey.wait(@receipts) }.should raise_error(Donkey::NoBlockGiven)
    end
  end
  

  context "public" do
    it "calls without a tag" do
      mock(@ticketer).next { "next-ticket" }
      mock(@public).call("to","data","next-ticket",{:foo => :bar})
      @donkey.call("to","data",{:foo => :bar}).should == Donkey::Receipt.new(@donkey,"next-ticket")
    end

    it "calls with a tag" do
      mock(@public).call("to","data","tag",{:foo => :bar})
      @donkey.call("to","data",{:tag => "tag", :foo => :bar}).should == Donkey::Receipt.new(@donkey,"tag")
    end

    it "replies" do
      reply_to = "reply_name#reply_id"
      mock(@header).reply_to { reply_to }
      mock(@header).message_id { "tag" }
      opts = { :foo => :bar }
      mock(@private).back(reply_to,"result","tag",opts)
      @donkey.back(@header,message=Object.new,"result",opts)
    end
  end

  context "topic" do
    it "listens" do
      mock(@topic).listen("name","key")
      @donkey.listen("name","key")
    end

    it "unlistens" do
      mock(@topic).unlisten("name","key")
      @donkey.unlisten("name","key")
    end

    it "generates event" do
      mock(@topic).event("name","key","data",dummy_opts)
      @donkey.event("name","key","data",dummy_opts)
    end

    it "creates topic" do
      mock(Donkey).channel { mock!.topic("name",dummy_opts).subject }
      Donkey.topic("name",dummy_opts)
    end
  end
  
  context "fanout" do
    before do
      #stub(@fanout).bcall.
    end
    it "fanout calls" do
      mock(@fanout).bcall("to","data","tag",{})
      mock(Donkey::Signaler).new(@signal_map,"tag") { "signaler" }.yields
      call = mock!.here.subject
      @donkey.bcall("to","data",:tag => "tag") { call.here }.should == "signaler"
    end
    
    it "calls without a tag" do
      mock(@ticketer).next { "next-ticket" }
      mock(@fanout).bcall("to","data","next-ticket",dummy_opts)
      @donkey.bcall("to","data",dummy_opts) { }
    end

    it "calls with a tag" do
      mock(@fanout).bcall("to","data","tag",dummy_opts)
      @donkey.bcall("to","data",dummy_opts.merge(:tag => "tag")) { }
    end

    it "raises if bcalling without a block" do
      lambda { @donkey.bcall("to","data",dummy_opts) }.should raise_error(Donkey::NoBlockGiven)
    end

    it "bcasts" do
      mock(@fanout).bcast("to","data",dummy_opts)
      @donkey.bcast("to","data",dummy_opts)
    end

    it "bbacks" do
      reply_to = "reply_name#reply_id"
      mock(@header).reply_to { reply_to }
      mock(@header).message_id { "tag" }
      opts = { :foo => :bar }
      mock(@fanout).bback(reply_to,"result","tag",opts)
      @donkey.bback(@header,message=Object.new,"result",opts)
    end
  end

end

