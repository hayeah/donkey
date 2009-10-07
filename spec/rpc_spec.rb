require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'

require 'eventmachine'
EM.threadpool_size = 1

describe "RPC" do
  before do
    q = Queue.new
    @server = nil
    @thread = Thread.new {ASS.start(:logging => false) {
        q << :ready
      }}
    @thread.abort_on_exception = true
    q.pop.should == :ready
  end

  after do
    ASS.stop
    @thread.join
  end

  it "should make synchronized call" do
    ASS.actor("spec") {
      def foo(i)
        i
      end
    }
    rpc = ASS.rpc
    futures = 100.times.map { |i| rpc.call("spec",:foo,i) }
    rspec_thread = Thread.current
    futures.each_with_index { |f,i|
      f.should be_an(ASS::RPC::Future)
      f.wait(5) {
        raise "timeout"
      }.should == i
      f.done?.should == true
      f.timeout?.should == false
    }
  end

  it "should timeout call" do
    ASS.actor("spec") {
      def foo(i)
        discard
      end
    }
    rpc = ASS.rpc
    rpc.call("spec",:foo,1).wait(1) { :timeout }.should == :timeout
  end

  it "should make call information available to waited future" do
    ASS.actor("spec") {
      def foo(i)
        i
      end
    }
    rpc = ASS.rpc
    futures = 10.times.map { |i| rpc.call("spec",:foo,i,{},i) }
    futures.each_with_index { |f,i|
      f.wait(5) {
        raise "timeout"
      }
      f.header.should be_a(MQ::Header)
      f.method.should == :foo
      f.meta.should == i
      f.data.should == i
    }
  end
  
end
