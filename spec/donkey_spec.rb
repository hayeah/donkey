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
    @waiter_map = Object.new
    @ticketer = Object.new
    stub(Donkey::WaiterMap).new { @waiter_map }
    stub(Donkey::Ticketer).new { @ticketer }

    @donkey = Donkey.new("name",@reactor)
    stub(@donkey).public { @public }
    stub(@donkey).private { @private }
    stub(@donkey).topic { @topic }
  end

  it "creates routes" do
    mock(Donkey::Route::Public).declare(@donkey)
    mock(Donkey::Route::Private).declare(@donkey)
    mock(Donkey::Route::Topic).declare(@donkey)
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

