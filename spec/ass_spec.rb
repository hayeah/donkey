require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'

describe "ASS" do
  include Rant::Check

  it "should start and stop" do
    check(30) do
      q = Queue.new
      s = nil
      thread = Thread.new {
        ASS.start {
          s = ASS.server("spec") do
            define_method(:on_call) do |i|
              q << :ok
            end
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
    q = Queue.new
    s = nil
    t = Thread.new {
      ASS.start {
        s = ASS.server("spec") {
          define_method :on_call do |i|
            raise "ouch" if i == :die
            q << :ok
            i
          end
        }
        q << :ready
      }
      q << :died
    }
    q.pop.should == :ready
    s.cast("spec",1)
    q.pop.should == :ok
    s.call("spec",:die)
    q.pop.should == :died
    EM.reactor_running?.should == false
  end
  
  describe "server" do
    before do
      p [:starting]
      q = Queue.new
      @server = nil
      @thread = Thread.new {ASS.start {
          q << :ready
        }}
      @thread.abort_on_exception = true
      p [@thread]
      q.pop.should == :ready
      p [:started]
    end

    after do
      p [:stopping]
      ASS.stop
      @thread.join
      p [:stopped]
    end

    it "should process message with on_call" do
      input = Queue.new
      output = Queue.new
      s = ASS.server("spec") {
        define_method(:on_call) do |i|
          input << i if i == 0
          output << i if i == 1 # this is the response to self
          i + 1
        end
      }
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
      s0 = ASS.server("spec") {
        define_method :on_call do |i|
          q0 << i
          i
        end
      }
      s1 = ASS.server("spec",:key => "s1") {
        define_method :on_call do |i|
          q1 << i
          i
        end
      }
      s2 = ASS.server("spec",:key => "s2") {
        define_method :on_call do |i|
          q2 << i
          i
        end
      }
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

    it "has some weirdness with pending, perhaps?" do
      pending
    end
    
  end
  
end

# describe "ASS" do
#   include Rant::Check

#   def client(opts={},&block)
#     c = ASS.client("spec",opts)
#     default = Proc.new {
#       def foo(i)
#         i
#       end
#     }
#     c.react(&(block || default))
#     c
#   end

#   describe "client" do
#     before do
#       @server = nil
#       @thread = Thread.new {
#         ASS.start {
#           @server = ASS.server("spec").react {
#             # default action
#             def foo(i)
#               i
#             end
#           }
#         }
#       }
#       @thread.abort_on_exception = true
#       Thread.pass
#     end

#     after do
#       ASS.stop
#       @thread.join
#     end

#     it "should get response back from server" do
#       q = Queue.new
#       c = client {
#         define_method(:foo) do |i|
#           q << i
#         end
#       }
#       10.times do
#         c.call(:foo,1)
#       end
#       r = 10.times.map { q.pop }
#       r.should == 10.times.map { 1 }
#     end

#     it "should route messages to different clients by keys" do
#       q0 = Queue.new
#       q1 = Queue.new
#       q2 = Queue.new
#       c0 = client {
#         define_method :foo do |i|
#           q0 << i
#           i
#         end
#       }
#       s1 = client(:key => "s1") {
#         define_method :foo do |i|
#           q1 << i
#           i
#         end
#       }
#       s2 = client(:key => "s2") {
#         define_method :foo do |i|
#           q2 << i
#           i
#         end
#       }
#       10.times { c0.call(:foo,0) }
#       10.times { s1.call(:foo,1) }
#       10.times { s2.call(:foo,2) }
#       10.times { s1.call(:foo, 0, :key => "spec") }
#       10.times { s2.call(:foo, 0, :key => "spec") }
#       10.times { s1.call(:foo, 2, :key => "s2") }
#       10.times { s2.call(:foo, 1, :key => "s1") }
#       30.times.map { q0.pop }.uniq.should == [0]
#       20.times.map { q1.pop }.uniq.should == [1]
#       20.times.map { q2.pop }.uniq.should == [2]
#     end
    
#     it "should have user accessible error handling" do
#       pending 
#       q = Queue.new
#       c = client {
#         define_method(:foo) do |i|
#           q << i
#         end
#       }
#       10.times do
#         c.call(:bar,1) # unknown method
#       end
#       Thread.pass
#       EM.instance_variable_get("@threadpool").each { |t|
#         p t
#       }
#       r = 10.times.map { q.pop }.uniq
#       r.should == [1]
#     end
#   end

# #   it "should raise when using rpc in the same thread as EM" do
# #     t = Thread.new do
# #       ASS.start do
# #         c = ASS.client("spec")
# #         lambda { c.rpc }.should raise_error
# #         ASS.stop
# #       end
# #     end
# #     t.join
# #   end

# #   describe "rpc" do
# #     before do
# #       @server = nil
# #       @thread = Thread.new {
# #         ASS.start {
# #           echo = Proc.new {
# #             def foo(i)
# #               i
# #             end
# #           }
# #           @server = ASS.server("spec")
# #         }
# #       }
# #       @thread.abort_on_exception = true
# #       Thread.pass
# #     end

# #     after do
# #       ASS.stop
# #       @thread.join
# #     end

# #     def client
# #       ASS.client("spec")
# #     end
    
# #     it "should memoize rpc client of a client" do
# #       c = client
# #       c.rpc.should == c.rpc
# #     end

# #     it "should serve requests concurrently" do
# #       @server.react do
# #         define_method(:foo) do |i|
# #           sleep(i)
# #           i
# #         end
# #       end
# #       s1 = client
# #       t0 = Time.now
# #       f1 = s1.rpc.call(:foo,0.5)
# #       f2 = s1.rpc.call(:foo,0.5)
# #       r1,r2 = f1.wait, f2.wait
# #       t1 = Time.now
# #       (t1-t0).should be_close(0.5,0.2)
# #     end
    
# #     it "should consume from its unique queue (no multiplexing)"  do
# #       msgs = Queue.new # collect all the messages the server got
# #       @server.react do
# #         define_method(:foo) do |i|
# #           msgs << i
# #           i
# #         end
# #       end
# #       s1 = client
# #       s2 = client
# #       # the server should've processed message from both rpc clients
# #       msgs.size.times.map {
# #         msgs.pop
# #       }.uniq.sort == [1,2]
# #       # two different rpc clients
# #       s1.rpc.should_not == s2.rpc
# #       # make sure that even though the server
# #       # serves both clients, each client's stream
# #       # of messages don't get mixed up
# #       10.times.map {
# #         s1.rpc.call(:foo,1)
# #       }.map(&:wait).uniq.should == [1]

# #       10.times.map {
# #         s2.rpc.call(:foo,2)
# #       }.map(&:wait).uniq.should == [2]
# #     end
# #   end

  
# #   describe "multiprocessing:" do
# #     def with_workers(child,n=4)
# #       # fork off n worker processes
# #       begin
# #         pids = n.times.map do |i|
# #           if pid=fork
# #             pid
# #           else
# #             begin
# #               ASS.start(&child)
# #             ensure
# #               exit!(0)
# #             end
# #           end
# #         end
# #         thread = Thread.new { ASS.start { } }
# #         thread.abort_on_exception = true
# #         Thread.pass
# #         yield
# #         ASS.stop
# #         thread.join
# #         pids
# #       ensure
# #         pids.each { |pid| Process.kill("KILL",pid)} if pids
# #         Process.waitall
# #       end
# #     end

# #     describe "server" do
# #       it "should spread load" do
# #         server = Proc.new {
# #           ASS.server("spec").react {
# #             def foo(i)
# #               [Process.pid,i]
# #             end
# #           }}
# #         rs = nil
# #         pids = with_workers(server) do
# #           c = client
# #           rs = 300.times.map { |i| c.rpc.call(:foo,i) }.map { |future| future.wait }
# #         end
# #         rs.map { |(pid,i)| pid }.uniq.sort.should == pids.sort
# #         rs.map { |(pid,i)| i }.sort.should == (0..299).to_a
        
# #       end

# #       it "should 12 concurrent 0.1s tasks in less than 1 second" do
# #         begin
# #           EM.threadpool_size = 1 # force each worker to be single threaded when doing work.
# #           server = Proc.new {
# #             ASS.server("spec").react {
# #               def foo(i)
# #                 [Process.pid,i]
# #               end
# #             }}
# #           t0 = Time.now
# #           pids = with_workers(server) do
# #             c = client
# #             rs = 12.times.map { |i| c.rpc.call(:foo,i) }.map { |future| future.wait }
# #           end
# #           t1 = Time.now
# #           (t1-t0).should < 1
# #         ensure
# #           EM.threadpool_size = 20 # reset EM default
# #         end
# #       end
# #     end

# #     describe "client" do
# #       it "should spread load" do
# #         worker = Proc.new {
# #           c = ASS.client("spec",:key => "subprocess").react {
# #             def foo(i)
# #               # route back to test process
# #               p [:sub,Process.pid,service,i]
# #               #ASS.client("spec").call(:foo,[Process.pid,i])
# #               service.call(:foo,[Process.pid,i],:key => nil)
# #             end
# #           }
# #           c.cast(:ready,Process.pid)
# #         }
# #         answers = Queue.new
# #         pids = Queue.new
# #         with_workers(worker) do
# #           ASS.server("spec").react {
# #             def foo(i)
# #               p [header.reply_to,header.routing_key,i]
# #               #p [:server,i]
# #               i
# #             end

# #             define_method(:ready) do |pid|
# #               pids << pid
# #             end
# #           }
# #           c = ASS.client("spec").react {
# #             define_method(:answer) do |i|
# #               p [:answer,Process.pid]
# #               answers << i
# #             end
# #           }
# #           pids = 4.times.map { pids.pop }
# #           p [:ready,pids]
# #           100.times.map { |i|
# #             c.call(:foo,i,:key => "subprocess")
# #           }
# #         end
# #         sleep(60)
# #         @rs = 100.times.map {
# #           #r = answers.pop
# #         }
# #         p answers
        
# # #         rs.should include(:s1)
# # #         rs.should include(:s2)
# #       end
      
# #     end
    
    
# #   end

  
# end
