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

  class TestReactor < Donkey::Reactor
    class Data < Struct.new(:donkey,:header,:message)
    end

    class Timeout < RuntimeError
    end

    def initialize
      @queue = Queue.new
    end
    
    def process(donkey,header,message)
      @queue << Data.new(donkey,header,message)
      true
    end

    def pop(timeout=3)
      timer = EM::Timer.new(timeout) do
        @queue << Timeout.new
      end
      
      case r=@queue.pop
      when Data
        timer.cancel
        r
      when Timeout
        raise r
      end
    end
    
  end

  before(:each) do
    Donkey.stop
    Donkey::Rabbit.restart
    @reactor = TestReactor.new
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

  it "calls" do
    @donkey.call(@donkey.name,10)
    q = find_queue(@donkey.name)
    q.should_not be_nil
    q["messages"].should == 1
  end

  it "calls itself" do
    future = @donkey.call(@donkey.name,10)
    future.should be_a(Donkey::Future)
    q = find_queue(@donkey.name)
    q["messages"].should == 1
    @donkey.pop
    future.wait.should == 10
    q = find_queue(@donkey.name)
    q["messages"].should == 0
  end

  it "casts" do
    @donkey.cast(@donkey.name,10)
    q = find_queue(@donkey.name)
    q.should_not be_nil
    q["messages"].should == 1
  end

  it "pops one message" do
    @donkey.cast(@donkey.name,data="data1")
    @donkey.cast(@donkey.name,data="data2")
    # pop first message
    @donkey.pop
    r = @reactor.pop
    r.header.should be_a(MQ::Header)
    r.message.should be_a(Donkey::Message::Cast)
    r.message.data.should == "data1"
    find_queue(@donkey.name)["messages"].should == 1
    # pop second message
    @donkey.pop
    r = @reactor.pop
    r.message.data.should == "data2"
    find_queue(@donkey.name)["messages"].should == 0
  end
  
  # it "pops with ack" do
#     pending
#   end

end
