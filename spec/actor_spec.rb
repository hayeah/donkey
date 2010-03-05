require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Actor::Processor" do
  before do
    @queue = Object.new
    @actor = Object.new
    stub(@queue).pop { @actor }
    stub(Queue).new { @queue }
    @thread = Object.new
    stub(Thread).new { @thread }
    @processor = Donkey::Actor::Processor.new
  end

  it "creates a queue" do
    @processor.thread.should == @thread
    @processor.queue.should == @queue
  end

  it "processes next" do
    mock(@actor).process { throw :break }
    mock(@queue).pop { @actor }
    catch(:break) { @processor.background_process_loop }
  end

  it "enqueues" do
    mock(@queue).enq(@actor)
    @processor.enqueue(@actor)
  end
end

describe "Donkey::Actor" do
  before do
    @donkey = Object.new
    @header = Object.new
    @message = Object.new
  end

  def actor(ack)
    @actor = Donkey::Actor.new(@donkey,@header,@message,ack)
  end

  def call(method,args,ack=false)
    @message = Donkey::Message::Call.new({"method" => method, "args" => args})
    actor(ack)
  end

  def call_foo(ack=false)
    call(:foo,[1,2],ack)
  end

  it "self.process" do
    processor = Object.new
    mock(processor).enqueue(is_a(Donkey::Actor))
    mock(Donkey::Actor).processor { processor }
    Donkey::Actor.process(@donkey,@header,@message,true)
  end
  
  context "#process" do
    it "acks if needed" do
      call_foo(true)
      mock(@actor).ack
      mock(@actor).on_call
      @actor.process
    end

    it "doesn't ack unless needed" do
      call_foo
      dont_allow(@actor).ack
      mock(@actor).on_call
      @actor.process
    end
  end

  it "calls" do
    call_foo
    mock(@actor).dispatch { "dispatch-result" }
    mock(@actor).reply("dispatch-result")
    @actor.process
  end

  it "dispatches" do
    call("method",args=["arg1","arg2"])
    mock(@actor).send("method",*args)
    @actor.dispatch
  end
end
