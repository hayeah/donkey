require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

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
      callback = mock!.call(*@values).subject
      stub(@waiter).success_callback { callback }
      success
    end

    it "calls success_callback only if it's set" do
      mock(@waiter).success_callback { nil }
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

    it "calls timeout callback" do
      callback = mock!.call(@waiter).subject
      stub(@waiter).timeout_callback { callback }
      timeout
    end

    it "calls timeout_callback only if it's set" do
      mock(@waiter).timeout_callback { nil }
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

  context "#wait!" do
    before do
      stub(@map).register.with_any_args
      stub(@map).unregister.with_any_args
      @timer = Object.new
      stub(EM::Timer).new { @timer }
      @queue = Object.new
      stub(Queue).new { @queue }
      stub(@queue).pop
      @waiter = Donkey::Waiter.new(@map,@key1,@key2)
    end
    
    it "raises if success callback is already set" do
      @waiter = Donkey::Waiter.new(@map,@key1,@key2) { }
      lambda { @waiter.wait! }.should raise_error(Donkey::Waiter::CallbackAlreadySet)
    end

    it "raises if timeout callback is already set" do
      @waiter = Donkey::Waiter.new(@map,@key1,@key2)
      @waiter.timeout(10) { }
      lambda { @waiter.wait!(10) }.should raise_error(Donkey::Waiter::TimeoutAlreadySet)
    end

    it "sets success callback" do
      mock(@queue).enq(results=[1,2,3])
      mock(@queue).pop { [] }
      @waiter.wait!
      @waiter.success_callback.call(*results)
    end

    it "sets timeout callback" do
      mock(@queue).enq(:timeout)
      mock(@queue).pop { [] }
      @waiter.wait!(10)
      @waiter.timeout_callback.call
    end

    it "returns result" do
      mock(@queue).pop { [1,2,3] }
      @waiter.wait!.should == [1,2,3]
    end

    it "raises timeout" do
      mock(@queue).pop { :timeout }
      lambda { @waiter.wait! }.should raise_error(Donkey::Timeout)
    end
  end
end
