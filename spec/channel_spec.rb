require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::Channel" do
  context "open" do
    before(:each) do
      connection = Object.new
      mock(connection).connection_status
      mock(Donkey::Channel).ensure_eventmachine
      mock(AMQP).connect(is_a(Hash)) { connection }
      mock(MQ).new(connection)
    end
    
    it "uses default settings to initialize AMQP" do
      c = Donkey::Channel.open
      c.settings.should == Donkey::Channel.default_settings
    end

    it "overrides default settings to initialize AMQP" do
      c = Donkey::Channel.open(:foo => 10)
      c.settings.should == Donkey::Channel.default_settings.merge(:foo => 10)
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
