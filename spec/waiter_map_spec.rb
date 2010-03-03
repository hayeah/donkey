require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Donkey::WaiterMap" do
  before(:each) do
    @map = Donkey::WaiterMap.new
    @waiter1 = Object.new
    @waiter2 = Object.new
    @key1 = "key1"
    @key2 = "key2"
  end

  it "registers waiters" do
    @map.register(@waiter1,@key1)
    @map.waiters_of(@key1).should include(@waiter1)
    @map.register(@waiter2,@key2)
    @map.waiters_of(@key2).should include(@waiter2)
  end

  it "returns all waiters for a key" do
    @map.register(@waiter1,@key1)
    @map.register(@waiter2,@key1,@key2)
    s = @map.waiters_of(@key1)
    s.should include(@waiter1,@waiter2)
    s.should have(2).waiters
    s = @map.waiters_of(@key2)
    s.should include(@waiter2)
    s.should have(1).waiter
  end

  it "unregisters waiters under a key" do
    @map.register(@waiter1,@key1,@key2)
    @map.unregister(@waiter1,@key1)
    @map.waiters_of(@key1).should be_empty
    @map.waiters_of(@key2).should include(@waiter1)
  end

  it "deletes key if no more waiters are under that key" do
    @map.register(@waiter1,@key1)
    @map.map.should have(1).key
    @map.unregister(@waiter1,@key1)
    @map.map.should have(0).keys
  end

  it "does nothing unregistering an unregistered waiter" do
    @map.unregister(@waiter1,@key1,@key2)
  end

  it "signals waiters" do
    @map.register(@waiter1,@key1)
    @map.register(@waiter2,@key1,@key2)
    mock(@waiter1).signal(@key1,1)
    mock(@waiter2).signal(@key1,1).then.signal(@key2,2)
    @map.signal(@key1,1)
    @map.signal(@key2,2)
  end
end
