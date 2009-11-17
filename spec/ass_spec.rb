require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'

require 'eventmachine'
EM.threadpool_size = 1

describe "ASS" do
  include Rant::Check

  def server(*args,&block)
    name = args.grep(String).first || "spec"
    opts = args.grep(Hash).first || {}
    ASS.server(name,opts) {
      define_method(:on_call,&block)
    }
  end

  def call(data,opts={},meta=nil)
    ASS.call("spec",nil,data,{
               :reply_to => "spec"
             }.merge(opts),meta)
  end

  def cast(data,opts={},meta=nil)
    ASS.cast("spec",nil,data,opts,meta)
  end


  it "should start and stop" do
    30.times do
      begin
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
        cast(0)
        q.pop.should == :ok
        ASS.stop
        q.pop.should == :done
      rescue => e
        ASS.stop
        raise e
      end
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
      cast(1)
      q.pop.should == :ok
      call(:die)
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

  
  it "should resend a message if server did not ack a message" do
    begin
      old_stderr = $stderr
      error_output = StringIO.new
      $stderr = error_output
      q = Queue.new
      s = nil
      t1 = Thread.new {
        ASS.start {
          s = ASS.server("spec").react(:ack => true) do
            define_method(:on_call) do |i|
              raise "ouch" if i == :die
              q << [header,i]
              i
            end
          end
          q << :ready
        }
        q << :died
      }
      q.pop.should == :ready
      cast(1)
      header, msg = q.pop
      msg.should == 1
      header.redelivered != true
      cast(:die)
      q.pop.should == :died
      t1.join
      $stderr.string.should_not be_empty
      EM.reactor_running?.should == false

      # restart server to get have the message resent
      t2 = Thread.new {
        ASS.start {
          s = server { |msg|
            q << [header,msg]
          }
        }
      }
      header, msg = q.pop
      msg.should == :die
      header.redelivered == true
      ASS.stop
      t2.join
    ensure
      $stderr = old_stderr
      ASS.stop
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
      10.times { call(0) }
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
      10.times { call(0) }
      10.times {
        msgs.pop.should == 0
        #errors.pop.is_a?(Exception).should == true
        errors.pop.should be_a(RuntimeError)
      }
    end

    it "should have access to magic service methods" do
      q = Queue.new
      s = server { |i|
        q << [header,method,data,meta]
      }
      cast(1,{},:meta)
      header,method,data,meta = q.pop
      header.should be_an(MQ::Header)
      method.should be_nil
      data.should == 1
      meta.should == :meta
    end


    it "should use a new callback instance to process each request" do
      q = Queue.new
      s = server { |i|
        q << self
        i
      }
      2000.times {|i|
        begin
          cast(1)
        rescue => e
          p "broken at #{i}"
          raise e
        end
      }
      # we need to hold on to the saved pointers,
      # otherwise objects would get garbage
      # collected and their object_ids
      # reused. This is the case with C-ruby.
      saved_pointers = []
      ids = (0...2000).map {
        o = q.pop
        saved_pointers << o
        o.object_id
      }
      #pp s.objs
      ids.uniq.length.should == ids.length
    end
    
    it "should receive messages in order from a connection" do
      q = Queue.new
      s = server do |i|
        q << i
        i
      end
      100.times { |i|
        cast(i)
      }
      100.times { |i|
        q.pop == i
      }
    end

    it "should resend message" do
      i = 0
      q = Queue.new
      s = server do |data|
        q << [header,method,data,meta]
        # requeue the first 100 messages
        i += 1
        if i <= 100
          resend
        end
        true
      end
      100.times { |i|
        cast(i,{ :message_id => i }, i)
      }
      # the first 100 should be the same message as the messages to 200
      
      msgs100 = 100.times.map { q.pop }
      msgs200 = 100.times.map { q.pop }
      msgs100.zip(msgs200) { |m1,m2|
        header1,method1,data1,meta1 = m1
        header2,method2,data2,meta2 = m2

        # everything should be the same except the delivery_tag
        header2.delivery_tag.should_not == header1.delivery_tag
        # requeue is different from AMQP's redelivery
        ## it should resend the message as another one.
        header1.redelivered.should_not == true
        header2.redelivered.should_not == true
        
        header2.message_id.should == header2.message_id
        method2.should == method1
        data2.should == data1
        meta1.should == meta2
      }
    end

    it "unsubscribes from queue" do
      q1 = Queue.new
      s1 = server do |data|
        q1 << data
      end
      (1..10).map { |i| cast(i) }
      (1..10).map { q1.pop }.should == (1..10).to_a
      # s1.stop { q1 << :unsubscribed } # lame, this somehow causes blocking.
#       q1.pop.should == :unsubscribed
      sleep(1)
      (1..10).map { |i| cast(i) } # these should be queued until another server comes up
      q1.should be_empty
      q2 = Queue.new
      s2 = server do |data|
        q2 << data
      end
      (1..10).map { q2.pop }.should == (1..10).to_a
    end
    
  end
  
end
