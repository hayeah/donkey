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

  it "should make synchronized rpc call" do
    ASS.actor("spec") do
      def foo(i)
        i
      end
    end
    c = ASS.client
    c.call("spec",:foo,1).wait.should == 1
  end

  it "should do cast" do
    q = Queue.new
    ASS.actor("spec") do
      define_method(:foo) do |i|
        q << i
        i
      end
    end
    c = ASS.client
    c.cast("spec",:foo,1)
    q.pop.should == 1
  end
end

  
