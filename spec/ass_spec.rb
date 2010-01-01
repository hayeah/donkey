require 'rubygems'
require "lib/ass"
require "spec"
require 'thread'

require 'eventmachine'
EM.threadpool_size = 1

require 'mocha'
Spec::Runner.configure do |config|
  config.mock_with :mocha
end


describe "ASS" do
  def server(*args,&block)
    name = args.grep(String).first || "spec"
    opts = args.grep(Hash).first || {}
    ASS.server(name,opts) do
      define_method(:on_cast,&block)
    end
  end

  def call(data,meta=nil,opts={})
    ASS.call("spec","spec",method=:test,data,meta,opts)
  end

  def cast(data,meta=nil,opts={})
    ASS.cast("spec",method=:test,data,meta,opts)
  end

  def start_ass
    t = Thread.current
    @thread = Thread.new {
      ASS.start(:logging => (ENV["trace"]=="true")) {
        t.wakeup
      }}
    @thread.abort_on_exception = true
    Thread.stop
  end

  def start_ass
    q = Queue.new
    @thread = Thread.new {
      ASS.start(:logging => (ENV["trace"]=="true")) {
        q << :ok
      }}
    @thread.abort_on_exception = true
    q.pop
  end

  def stop_ass
    ASS.stop
    @thread.join
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
    pending
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
    # test this when on_exit is implemented
    pending
    begin
      old_stderr = $stderr
      error_output = StringIO.new
      $stderr = error_output
      q = Queue.new
      s = nil
      t1 = Thread.new {
        ASS.start {
          s = ASS.server("spec").react(:ack => true) do
            define_method(:on_cast) do |i|
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
      cast(:die) rescue :ok
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

  describe "serialization formats" do
    def test_format(format)
      q = Queue.new
      @thread = Thread.new {
        ASS.start(:format => format
                  #:logging => true
                  ) {
          q << :ready
        }}
      @thread.abort_on_exception = true
      q.pop.should == :ready

      server { |*args|
        # do nothing
        q << :got_msg
      }
      cast(:whatever)
      q.pop.should == :got_msg
      
      ASS.stop
      @thread.join
    end

    it "uses Marshal" do
      ASS::Marshal.expects(:dump).returns("whatever")
      ASS::Marshal.expects(:load).returns({"type" => "cast"})
      test_format(ASS::Marshal)
    end

    it "uses JSON" do
      ASS::JSON.expects(:dump).returns("whatever")
      ASS::JSON.expects(:load).returns({"type" => "cast"})
      test_format(ASS::JSON)
    end

    it "uses BERT" do
      ASS::BERT.expects(:dump).returns("whatever")
      ASS::BERT.expects(:load).returns({"type" => "cast"})
      test_format(ASS::BERT)
    end

    it "uses JSON" do
      ASS::JSON.expects(:dump).returns("whatever")
      ASS::JSON.expects(:load).returns({"type" => "cast"})
      test_format(ASS::JSON)
    end
  end

  describe "callback" do
    def server
      s = mock("server",:ack? => true)
      s.stubs(:name => "mock-server")
      s
    end

    def header
      mock("header",:ack => true)
    end
    
    context "factory building" do
      it "creates subclass from Proc" do
        f = ASS::Callback.factory {
          def on_cast
            :foobar
          end
        }
        f.new(nil,nil,nil).on_cast.should == :foobar
      end
      
      it "uses a given class as is" do
        c = Class.new(ASS::Callback) do
          def on_cast
            :foobar
          end
        end
        f = ASS::Callback.factory(c)
        f.new(nil,nil,nil).on_cast.should == :foobar
      end

      it "raises if class is not a subclass of Callback" do
        c = Class.new
        lambda {
          ASS::Callback.factory(c)
        }.should raise_error
      end
      
      it "subclasses then includes a module" do
        m = Module.new do
          def on_cast
            :foobar
          end
        end
        f = ASS::Callback.factory(m)
        f.new(nil,nil,nil).on_cast.should == :foobar
      end

      # it "delegates to a singleton" do
      #         pending
      #       end
      
    end

    it "processes with attributes set" do
      f = ASS::Callback.factory{}.new(:server,:header,:content)
      f.server.should == :server
      f.header.should == :header
      f.content.should == :content
    end

    def handler(content={"type" => "cast","data" => 0})
      f = ASS::Callback.factory {
        def on_cast(data)
        end
      }
      f.new(server,header,content)
    end

    it "invokes on_cast" do
      o = handler
      o.expects(:on_cast).with(0)
      o.process!
    end

    it "acks if necessary" do
      o = handler
      o.process!
      o.acked?.should == true
    end
    
    it "invokes on_error when error is raised" do
      f = ASS::Callback.factory {
        def on_cast(data)
          raise "foobar"
        end
      }
      o = f.new(server,header,{"type" => "cast"})
      o.expects(:on_error)
      o.process!
      o.acked?.should == true
    end

    it "reraises error raised in on_error" do
      f = ASS::Callback.factory {
        def on_cast(data)
          raise "foobar"
        end

        def on_error(e)
          raise "aiyeee"
        end
      }
      o = f.new(server,header,{"type" => "cast"})
      lambda { o.process! }.should raise_error
    end

    it "invokes on_call" do
      s = server
      f = ASS::Callback.factory {}
      o = f.new(s,header,{
                  "type" => "call",
                  "from" => "from-test",
                  "method" => "test-method",
                  "data" => 0,
                  "meta" => "meta",
                  "tag" => "tag"
                })
      test_result = 10
      o.expects(:on_call).with(0).returns(test_result)
      ASS.expects(:back).with("from-test",s.name,"test-method",test_result,"tag","meta")
      o.process!
      o.acked?.should == true
    end
    
  end
  
  describe "server" do
    def server(&block)
      ASS.server("spec",&block)
    end
    
    before do
      start_ass
    end

    after do
      stop_ass
    end
    

    it "processes message" do
      input = Queue.new
      output = Queue.new
      server {
        define_method(:on_call) do |n|
          input << n
          n + 1
        end

        define_method(:on_back) do |n|
          output << n
        end
        
      }
      10.times { call(0) }
      10.times.map { input.pop }.uniq.should == [0]
      10.times.map { output.pop }.uniq.should == [1]
    end
    

    it "should be killed by uncaught error" do
      t = Thread.current
      s = ASS.server("spec") {
        define_method(:on_cast) do |_|
          t.wakeup
          raise "aieee"
        end
      }
      begin
        # swallow output
        old_stderr = $stderr
        $stderr = StringIO.new("")
        lambda {
          cast(0)
          Thread.stop
        }.should raise_error
      ensure
        $stderr = old_stderr
      end
    end

    it "gets header and content from AMQP" do
      q = Queue.new
      s = server do |i|
        define_method(:on_cast) do |data|
          t = Thread.current
          t[:header]  = header
          t[:content] = content
          t[:data]    = data
          q << :ok
        end
      end
      cast(1)
      q.pop.should == :ok
      t = s.thread
      t[:header].should be_an(MQ::Header)
      t[:content].should be_a(Hash)
      t[:content].should include(*%w(type method data))
      t[:data].should == 1
    end


    # it "should resend message" do
#       pending
#       i = 0
#       q = Queue.new
#       s = server do |data|
#         q << [header,method,data,meta]
#         # requeue the first 100 messages
#         i += 1
#         if i <= 100
#           resend
#         end
#         true
#       end
#       100.times { |i|
#         cast(i,{ :message_id => i }, i)
#       }
#       # the first 100 should be the same message as the messages to 200
      
#       msgs100 = 100.times.map { q.pop }
#       msgs200 = 100.times.map { q.pop }
#       msgs100.zip(msgs200) { |m1,m2|
#         header1,method1,data1,meta1 = m1
#         header2,method2,data2,meta2 = m2

#         # everything should be the same except the delivery_tag
#         header2.delivery_tag.should_not == header1.delivery_tag
#         # requeue is different from AMQP's redelivery
#         ## it should resend the message as another one.
#         header1.redelivered.should_not == true
#         header2.redelivered.should_not == true
        
#         header2.message_id.should == header2.message_id
#         method2.should == method1
#         data2.should == data1
#         meta1.should == meta2
#       }
#     end

    it "unsubscribes from queue" do
      pending
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
