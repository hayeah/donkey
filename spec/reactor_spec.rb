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

  def bcast(ack=false)
    @message = Donkey::Message::BCast.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message,ack)
  end

  def bcall(ack=false)
    @message = Donkey::Message::BCall.new("data")
    @reactor = Donkey::Reactor.new(@donkey,@header,@message,ack)
  end

  def bback(ack=false)
    stub(@header).message_id { "message_id" }
    @message = Donkey::Message::BBack.new("data")
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
    def call_reply
      call
      @result = "result"
      mock(@donkey).back(@header,@message,@result,is_a(Hash))
      @reactor.reply(@result)
    end

    def bcall_reply
      bcall
      @result = "result"
      mock(@donkey).bback(@header,@message,@result,is_a(Hash))
      @reactor.reply(@result)
    end
    
    it "replies" do
      call_reply
    end
    
    it "raises if replied twice" do
      call_reply
      lambda { @reactor.reply(@result) }.should raise_error(Donkey::Error)
    end

    it "returns true if already replied" do
      call_reply
      @reactor.replied?.should == true
    end

    it "replies to bcall" do
      bcall_reply
    end
  end

  context "#process" do
    it "processes BCall" do
      bcall
      mock(@reactor).on_bcall
      @reactor.process
    end

    it "processes BCast" do
      bcast
      mock(@reactor).on_bcast
      @reactor.process
    end

    it "processes BBack" do
      bback
      mock(@donkey).signal(@header.message_id,@message.data)
      @reactor.process
    end
    
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
