require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

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

  def event(ack=false)
    @message = Donkey::Message::Event.new("data")
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

    it "processes Event" do
      event
      mock(@reactor).on_event
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
