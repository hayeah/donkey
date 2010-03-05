require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Signaler" do
  before do
    @signal_map = Object.new
    stub(@signal_map).register.with_any_args
    @key = "key"
    @signal_callback = lambda { |r| }
  end

  def signaler
    @signaler = Donkey::Signaler.new(@signal_map,@key,&@signal_callback)
  end

  context "#signal" do
    it "signals" do
      call = mock!.here("value").subject
      @signal_callback = lambda { |r| call.here(r) }
      signaler.signal(@key,"value")
    end

    it "signals multiple times" do
      call = mock!.here("value").twice.subject
      @signal_callback = lambda { |r| call.here(r) }
      signaler.signal(@key,"value")
      signaler.signal(@key,"value")
    end
  end

  context "#timeout" do
    before do
      signaler
      @timeout = 10
      @timeout_callback = lambda { |*args| }
      @timer = Object.new
      stub(EM).add_timer{ @timer }.with_any_args
      stub(@signaler).on_timeout
    end
    
    def set_timeout
      @signaler.timeout(@timeout,&@timeout_callback)
    end

    it "registers itself to signal_map" do
      mock(@signal_map).register(is_a(Donkey::Signaler),@key)
      set_timeout
    end

    it "raises error if timeout already set" do
      set_timeout
      lambda { set_timeout }.should raise_error(Donkey::TimeoutAlreadySet)
    end

    it "raises error if signal callback is not set" do
      @signaler = Donkey::Signaler.new(@signal_map,@key)
      lambda { set_timeout }.should raise_error(Donkey::NoBlockGiven)
    end

    it "returns waiter instance" do
      set_timeout.should == @signaler
    end

    it "sets timeout timer" do
      a_timer = Object.new
      mock(@signaler).on_timeout
      mock(EM::Timer).new(@timeout) { a_timer }.yields
      set_timeout
      @signaler.timer.should == a_timer
    end
    
    it "sets timeout callback" do
      set_timeout
      @signaler.timeout_callback.should == @timeout_callback
    end
  end

  context "#on_timeout" do
    before do
      signaler
      @lambda = Object.new
      stub(@lambda).call
    end
    
    def timeout
      stub(@signaler).timeout_callback { @lambda }
      stub(@signal_map).unregister.with_any_args
      @signaler.send(:on_timeout)
    end
    
    it "does nothing if signaler is already done" do
      mock(@signaler).done? { true }
      @lambda = mock!.call.never.subject
      timeout
    end

    it "completes" do
      @signaler.done?.should == false
      timeout
      @signaler.done?.should == true
    end

    it "calls timeout block" do
      mock(@lambda).call
      timeout
    end

    it "unregisters itself" do
      mock(@signal_map).unregister(@signaler,@key)
      timeout
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
      signaler
    end

    def signaler(&block)
      @signaler = Donkey::Signaler.new(@map,@key,&block)
    end
    
    it "raises if success callback is already set" do
      signaler { }
      lambda { @signaler.wait!(10) }.should raise_error(Donkey::CallbackAlreadySet)
    end
    
    it "sets signal callback" do
      mock(@queue).enq(1)
      mock(@queue).enq(2)
      mock(@queue).enq(3)
      mock(@queue).size { 3 }
      mock(@queue).pop.times(3)
      mock(@queue).pop { :timeout }
      @signaler.wait!(10)
      @signaler.signal_callback.call(1)
      @signaler.signal_callback.call(2)
      @signaler.signal_callback.call(3)
    end

    it "sets timeout callback" do
      mock(@queue).enq(:timeout)
      mock(@queue).pop { [] }
      mock(@queue).size { 0 }
      @signaler.wait!(10)
      @signaler.timeout_callback.call
    end

    it "returns result" do
      stub(@queue).pop.returns { 1 }
      mock(@queue).size { 2 }
      @signaler.wait!(10).should == [1,1]
    end
  end
end
