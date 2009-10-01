require 'rubygems'
require "lib/ass"
require "spec"
require 'rant/spec'
require 'thread'

describe "ASS" do
  include Rant::Check

  

  describe "client" do
  end

  it "should raise when using rpc in the same thread as EM" do
    t = Thread.new do
      ASS.start do
        c = ASS.client("spec")
        lambda { c.rpc }.should raise_error
        ASS.stop
      end
    end
    t.join
  end

  
  describe "rpc" do
    before do
      @server = nil
      @thread = Thread.new {
        ASS.start {
          echo = Proc.new {
            def foo(i)
              i
            end
          }
          @server = ASS.server("spec")
        }
      }
      @thread.abort_on_exception = true
      Thread.pass
    end

    after do
      ASS.stop
      @thread.join
    end

    def client
      ASS.client("spec", :auto_delete => true)
    end
    
    it "should memoize rpc client of a client" do
      c = client
      c.rpc.should == c.rpc
    end

    it "should serve requests concurrently" do
      @server.react do
        define_method(:foo) do |i|
          sleep(i)
          i
        end
      end
      c1 = client
      t0 = Time.now
      f1 = c1.rpc.call(:foo,0.6)
      f2 = c1.rpc.call(:foo,0.6)
      r1,r2 = f1.wait, f2.wait
      t1 = Time.now
      (t1-t0).should < 1
    end
    
    it "should consume from its unique queue (no multiplexing)"  do
      msgs = Queue.new # collect all the messages the server got
      @server.react do
        define_method(:foo) do |i|
          msgs << i
          i
        end
      end
      c1 = client
      c2 = client
      # the server should've processed message from both rpc clients
      msgs.size.times.map {
        msgs.pop
      }.uniq.sort == [1,2]
      # two different rpc clients
      c1.rpc.should_not == c2.rpc
      # make sure that even though the server
      # serves both clients, each client's stream
      # of messages don't get mixed up
      10.times.map {
        c1.rpc.call(:foo,1)
      }.map(&:wait).uniq.should == [1]

      10.times.map {
        c2.rpc.call(:foo,2)
      }.map(&:wait).uniq.should == [2]
    end
  end

  
  describe "server multiple server instances" do
    def with_servers(actor,n=4)
      # fork off n worker processes
      begin
        pids = n.times.map do |i|
          if pid=fork
            pid
          else
            # child
            begin
              ASS.start do
                ASS.server("spec").react &actor
              end
            ensure
              exit!(0)
            end
            
          end
        end
        client = nil
        client_thread = Thread.new do
          ASS.start do
            client = ASS.client("spec")
          end
        end
        client_thread.abort_on_exception = true
        Thread.pass
        yield(client)
        ASS.stop
        client_thread.join
        pids
      ensure
        pids.each { |pid| Process.kill("KILL",pid)} if pids
        Process.waitall
      end
    end

    it "should spread load onto worker processes" do
      server = Proc.new {
        def foo(i)
          [Process.pid,i]
        end
      }
      rs = nil
      pids = with_servers(server) do |c|
        rs = 300.times.map { |i| c.rpc.call(:foo,i) }.map { |future| future.wait }
      end
      rs.map { |(pid,i)| pid }.uniq.sort.should == pids.sort
      rs.map { |(pid,i)| i }.sort.should == (0..299).to_a
    end

    it "should 12 concurrent 0.1s tasks in less than 1 second" do
      begin
        EM.threadpool_size = 1 # force each worker to be single threaded when doing work.
        server = Proc.new {
          def foo(i)
            sleep(0.1)
            i
          end
        }
        t0 = Time.now
        pids = with_servers(server) do |c|
          rs = 12.times.map { |i| c.rpc.call(:foo,i) }.map { |future| future.wait }
        end
        t1 = Time.now
        (t1-t0).should < 1
      ensure
        EM.threadpool_size = 20 # reset EM default
      end
      
    end
  end

  
end
