require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'

require 'eventmachine'
EM.threadpool_size = 1

describe "Actor" do
  before do
    q = Queue.new
    @server = nil
    @thread = Thread.new {ASS.start {
        q << :ready
      }}
    @thread.abort_on_exception = true
    q.pop.should == :ready
  end

  after do
    ASS.stop
    @thread.join
  end
  
  it "should respond by dispatch to methods" do
    q = Queue.new
    actor = ASS.actor("spec") {
      define_method(:foo) do |i|
        r = [:foo,i]
        q << r
        r
      end

      define_method(:bar) do |i|
        r = [:bar,i]
        q << r
        r
      end
    }
    #a.cast("spec",:foo,1)
    actor.cast("spec",:foo,1)
    q.pop.should == [:foo,1]
    actor.cast("spec",:bar,2)
    q.pop.should == [:bar,2]

    actor.call("spec",:bar,3) # calling to self
    q.pop.should == [:bar,3] # input
    q.pop.should == [:bar,[:bar,3]] # output
  end

  it "should handle error by calling on_error" do
    q = Queue.new
    actor = ASS.actor("spec") {
      define_method(:on_error) do |e,data|
        q << [e,data]
      end
    }
    actor.cast("spec",:foo,1)
    e, data = q.pop
    e.should be_a(NoMethodError)
    data.should == 1
  end

  it "should be able to make service calls" do
    q = Queue.new
    a1 = ASS.actor("spec") {
      define_method(:foo) do |i|
        q << [:foo,i]
        cast("spec2",:bar,i+1)
      end
    }
    a2 = ASS.actor("spec2") do
      define_method(:bar) do |i|
        q << [:bar,i]
      end
    end
    a1.cast("spec",:foo,1)
    q.pop.should == [:foo,1]
    q.pop.should == [:bar,2]
  end

  
end
