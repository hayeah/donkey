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
      lambda { set_timeout }.should raise_error(Donkey::Signaler::TimeoutAlreadySet)
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
  
end
