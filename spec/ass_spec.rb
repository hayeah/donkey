require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'


describe "ASS" do
  include Rant::Check

  def server(*args,&block)
    name = args.grep(String).first || "spec"
    opts = args.grep(Hash).first || {}
    ASS.server(name,opts) {
      define_method(:on_call,&block)
    }
  end

  it "should start and stop" do
    30.times do
      q = Queue.new
      s = nil
      thread = Thread.new {
        ASS.start {
          s = server("spec") do |i|
            q << :ok
          end
          q << :ready
        }
        q << :done
      }
      thread.abort_on_exception = true
      q.pop.should == :ready
      s.cast("spec",0)
      q.pop.should == :ok
      ASS.stop
      q.pop.should == :done
    end
  end

  it "should stop ASS if server does not respond to on_error" do
    begin
      old_stderr = $stderr
      error_output = StringIO.new
      $stderr = error_output
      q = Queue.new
      s = nil
      t = Thread.new {
        ASS.start {
          s = server("spec") do |i|
            raise "ouch" if i == :die
            q << :ok
            i
          end
          q << :ready
        }
        q << :died
      }
      q.pop.should == :ready
      s.cast("spec",1)
      q.pop.should == :ok
      s.call("spec",:die)
      q.pop.should == :died
      $stderr.string.should_not be_empty
      EM.reactor_running?.should == false
    rescue => e
      ASS.stop
      raise e
    ensure
      $stderr = old_stderr
    end
  end
  
  describe "server" do
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

    it "should process message with on_call" do
      input = Queue.new
      output = Queue.new
      s = server("spec") do |i|
        input << i if i == 0
        output << i if i == 1 # this is the response to self
        i + 1
      end
      # note that when calling self we have the
      # wierdness of the response sending back to
      # self.
      10.times { s.call("spec",0) }
      10.times.map { input.pop }.uniq.should == [0]
      10.times.map { output.pop }.uniq.should == [1]
    end

    it "should handle error with on_error" do
      errors = Queue.new
      msgs = Queue.new
      s = ASS.server("spec") {
        def on_call(i)
          raise "aieee"
        end

        define_method(:on_error) do |e,msg|
          msgs << msg
          errors << e
        end
      }
      10.times { s.call("spec",0) }
      10.times {
        msgs.pop.should == 0
        #errors.pop.is_a?(Exception).should == true
        errors.pop.should be_a(RuntimeError)
      }
    end

    it "should route according to key" do
      q0 = Queue.new
      q1 = Queue.new
      q2 = Queue.new
      s0 = server("spec") do |i|
        q0 << i
        i
      end
      s1 = server(:key => "s1") do |i|
        q1 << i
        i
      end
      s2 = server("spec",:key => "s2") do |i|
        q2 << i
        i
      end
      10.times { s0.cast("spec",0) }
      10.times { s1.cast("spec",1) }
      10.times { s2.cast("spec",2) }
      10.times { s1.cast("spec", 0, :key => "spec") }
      10.times { s2.cast("spec", 0, :key => "spec") }
      10.times { s1.cast("spec", 2, :key => "s2") }
      10.times { s2.cast("spec", 1, :key => "s1") }
      30.times.map { q0.pop }.uniq.should == [0]
      20.times.map { q1.pop }.uniq.should == [1]
      20.times.map { q2.pop }.uniq.should == [2]
    end

    it "should have access to magic service methods" do
      q = Queue.new
      s = server { |i|
        q << [header,method,data,meta]
      }
      s.cast("spec",1,{},:meta)
      header,method,data,meta = q.pop
      p header.class
      header.should be_an(MQ::Header)
      method.should be_nil
      data.should == 1
      meta.should == :meta
    end

    it "has some weirdness with pending, perhaps?" do
      pending
    end
    
  end
  
end
