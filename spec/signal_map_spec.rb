require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::SignalMap" do
  before(:each) do
    @map = Donkey::SignalMap.new
    @listener1 = Object.new
    @listener2 = Object.new
    @key1 = "key1"
    @key2 = "key2"
  end

  it "registers listeners" do
    @map.register(@listener1,@key1)
    @map.listeners_of(@key1).should include(@listener1)
    @map.register(@listener2,@key2)
    @map.listeners_of(@key2).should include(@listener2)
  end

  it "returns all listeners for a key" do
    @map.register(@listener1,@key1)
    @map.register(@listener2,@key1,@key2)
    s = @map.listeners_of(@key1)
    s.should include(@listener1,@listener2)
    s.should have(2).listeners
    s = @map.listeners_of(@key2)
    s.should include(@listener2)
    s.should have(1).listener
  end

  it "unregisters listeners under a key" do
    @map.register(@listener1,@key1,@key2)
    @map.unregister(@listener1,@key1)
    @map.listeners_of(@key1).should be_empty
    @map.listeners_of(@key2).should include(@listener1)
  end

  it "deletes key if no more listeners are under that key" do
    @map.register(@listener1,@key1)
    @map.map.should have(1).key
    @map.unregister(@listener1,@key1)
    @map.map.should have(0).keys
  end

  it "does nothing unregistering an unregistered listener" do
    @map.unregister(@listener1,@key1,@key2)
  end

  it "signals listeners" do
    @map.register(@listener1,@key1)
    @map.register(@listener2,@key1,@key2)
    mock(@listener1).signal(@key1,1)
    mock(@listener2).signal(@key1,1).then.signal(@key2,2)
    @map.signal(@key1,1)
    @map.signal(@key2,2)
  end
end
