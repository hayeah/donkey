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
end


context "messages" do
  class TestReactor < Donkey::Reactor
  end
  before(:each) do
    Donkey.stop
    Donkey::Rabbit.restart
    @donkey = Donkey.new("test",TestReactor)
    @donkey.create
    @q = Queue.new
  end

  def react(method,&block)
    TestReactor.class_eval do
      define_method(method,&block)
    end
  end

  it "pops"

  it "pops with ack"
  
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
end
