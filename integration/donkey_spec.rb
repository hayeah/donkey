require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'pp'

  
module RabbitHelper
  extend self
  def find_exchange(name)
    Donkey::Rabbit.exchanges.find { |h|
      h["name"] == name
    }
  end
  
  def find_queue(name)
    Donkey::Rabbit.queues.find { |h|
      h["name"] == name
    }
  end

  def find_binding(exchange_name,queue_name)
    Donkey::Rabbit.bindings.find { |h|
      h["exchange_name"] == exchange_name && h["queue_name"] == queue_name
    }
  end
end


describe "Donkey" do

  include RabbitHelper

  before(:each) do
    Donkey.stop
    Donkey::Rabbit.restart
    @reactor = Object.new
    Donkey.topic("test.topic")
    @donkey = Donkey.new("test",@reactor)
    @donkey.create
  end
  
  context "Rabbit" do
    it "has queues" do
      q = find_queue(@donkey.name)
      q.should include("memory")
      q.delete("memory")
      q.should == {
        "name"=>"test",
        "transactions"=> 0,
        "messages"=> 0,
        "messages_unacknowledged"=> 0,
        "arguments"=>"[]",
        "acks_uncommitted"=> 0,
        "messages_ready"=> 0,
        "auto_delete"=> false,
        "messages_uncommitted"=> 0,
        "consumers"=> 0,
        "durable"=> false}
      
    end
  end
  
  it "creates public route" do
    find_exchange(@donkey.name).should_not be_nil
    find_binding(@donkey.name,@donkey.name).should_not be_nil
    find_queue(@donkey.name).should_not be_nil
  end

  it "creates private route" do
    find_exchange(@donkey.name).should_not be_nil
    (b = find_binding(@donkey.name,@donkey.id)).should_not be_nil
    (q = find_queue(@donkey.id)).should_not be_nil
    q["auto_delete"].should == true
  end


  context "topic" do
    def name
      "test.topic"
    end
    it "creates topic exchange" do
      find_exchange(name).should_not be_nil
    end

    it "creates topic queue" do
      find_queue(name).should_not be_nil
    end

    it "creates topic binding" do
      @donkey.listen(name,"key")
      find_binding(name,name)["routing_key"].should == "key"
    end

    def bindings
      Donkey::Rabbit.bindings.select { |r|
        r["exchange_name"] == name && r["queue_name"] == name
      }
    end
    
    it "creates topic bindings" do
      @donkey.listen(name,"key1")
      @donkey.listen(name,"key2")
      bindings.should have(2).items
    end

    it "unbinds topic bindings" do
      @donkey.listen(name,"key1")
      @donkey.listen(name,"key2")
      bindings.should have(2).items
      @donkey.unlisten(name,"key1")
      bs = bindings
      bs.should have(1).items
      bs.find { |b| b["routing_key"] == "key1" }.should be_nil
      bs.find { |b| b["routing_key"] == "key2" }.should_not be_nil
    end
  end
end

context "messages" do
  include RabbitHelper

  def call(data,opts={})
    @donkey.call(@donkey.name,data,opts)
  end

  def cast(data,opts={})
    @donkey.cast(@donkey.name,data,opts)
  end

  def react(method,&block)
    TestReactor.class_eval do
      define_method(method,&block)
    end
  end

  def count(queue_name=@donkey.name)
    find_queue(queue_name)["messages"]
  end
  
  class TestReactor < Donkey::Reactor
  end
  
  before(:each) do
    Donkey.stop
    Donkey::Rabbit.restart
    Donkey.topic("test.topic")
    @donkey = Donkey.new("test",TestReactor)
    @donkey.create
    @q = Queue.new
  end

  it "pops empty queue" do
    q = Queue.new
    @donkey.pop { q << :empty }
    q.pop.should == :empty
  end

  it "pops" do
    cast(1)
    q = Queue.new
    react(:on_cast) {
      q << self
    }
    count.should == 1
    @donkey.pop
    reactor = q.pop
    count.should == 0
    reactor.ack?.should be_false
    reactor.message.data.should == 1
  end
  
  it "pops with ack" do
    cast(1)
    q = Queue.new
    react(:on_cast) {
      q << self
    }
    count.should == 1
    @donkey.pop(:ack => true)
    reactor = q.pop
    reactor.ack?.should be_true
    #  not yet acked, so message in queue count should still be 1
    count.should == 1
    reactor.ack
    sleep(1)
    count.should == 0
  end
  
  it "casts to itself" do
    @donkey.cast(@donkey.name,:input)
    q = Queue.new
    react(:on_cast) {
      q << message.data
    }
    @donkey.pop
    q.pop.should == :input
  end
  
  it "calls itself" do
    receipt = @donkey.call(@donkey.name,:input)
    q = Queue.new
    react(:on_call) {
      q << self
      reply(:output)
    }
    # @donkey.wait(receipt) { |output| q << output }
    waiter = receipt.wait { |output| q << output }
    waiter.should be_a(Donkey::Waiter)
    waiter.pending.should have(1).key
    waiter.pending.should include(receipt.key)
    
    @donkey.pop
    reactor = q.pop
    msg = reactor.message
    msg.should be_a(Donkey::Message::Call)
    msg.data.should == :input
    reactor.header.message_id.should == receipt.key

    q.pop.should == :output
    waiter.done?.should == true
    waiter.success?.should == true
    waiter.pending.should be_empty
    waiter.value(receipt.key).should == :output

    # waiter_map should not keep references to completed waiters
    @donkey.waiter_map.map.should be_empty
  end

  it "times out" do
    receipt = @donkey.call(@donkey.name,:timeout)
    q = Queue.new
    waiter = receipt.wait { |r|
      # do nothing
    }.timeout(0.5) {
      q << :timeout
    }
    q.pop.should == :timeout
    waiter.timeout?.should == true
  end
  
  it "waits multiple receipts" do
    r1 = call(1)
    r2 = call(2)
    q = Queue.new
    react(:on_call) {
      reply(message.data)
    }
    @donkey.wait(r1,r2) { |v1,v2|
      q << [v1,v2]
    }
    2.times { @donkey.pop }
    q.pop.should == [1,2]
  end

  it "subscribes" do
    q = Queue.new
    react(:on_cast) {
      q << self
    }
    rs = 10.times.map { |i| cast(i) }
    sleep(1)
    count.should == 10
    
    @donkey.subscribe
    reactors = 10.times.map { q.pop }
    count.should == 0
    reactors.each { |reactor|
      reactor.ack?.should == false
    }
    reactors.map { |r| r.message.data }.should == (0..9).to_a
  end

  it "subscribes with ack" do
    @donkey.subscribe(:ack => true)
    q = Queue.new
    react(:on_cast) {
      q << self
    }
    rs = 10.times.map { |i| cast(i) }
    reactors = 10.times.map { q.pop }
    count.should == 10
    reactors.each { |reactor|
      reactor.ack?.should == true
    }
    reactors.each(&:ack)
    sleep(1)
    count.should == 0
  end

  context "topic" do
    def exchange
      "test.topic"
    end

    it "gets an event" do
      q = Queue.new
      react(:on_event) {q << self}
      @donkey.listen(exchange,"#")
      @donkey.event(exchange,"key","data")
      @donkey.topic.pop
      reactor = q.pop
      reactor.header.exchange.should == exchange
      reactor.header.routing_key.should == "key"
      reactor.message.data.should == "data"
    end

    it "binds to multiple keys" do
      q = Queue.new
      react(:on_event) {q << self}
      @donkey.listen(exchange,"key1")
      @donkey.listen(exchange,"key2")
      @donkey.event(exchange,"key1",1)
      @donkey.event(exchange,"key2",2)
      count(@donkey.topic.queue.name).should == 2
      2.times { @donkey.topic.pop }
      2.times.map { q.pop.message.data }.sort.should == [1,2]
      @donkey.event(exchange,"key3",1)
      sleep(1)
      count(@donkey.topic.queue.name).should == 0
    end
  end
end