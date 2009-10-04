class ASS::RPC
  require 'thread'
  require 'monitor'
  
  class Future
    attr_reader :message_id
    attr_accessor :header, :data, :timeout
    def initialize(rpc,message_id)
      @message_id = message_id
      @rpc = rpc
      @timeout = false
      @done = false
    end
    
    def wait(timeout=nil,&block)
      @rpc.wait(self,timeout,&block) # synchronous call that will block
    end

    def done!
      @done = true
    end

    def done?
      @done
    end

    def timeout?
      @timeout
    end

    def inspect
      "#<#{self.class} #{message_id}>"
    end
  end

  class Reactor
    # want to minimize name conflicts here.
    def initialize(rpc)
      @rpc = rpc
    end

    def method_missing(_method,data)
      @rpc.buffer << [header,data]
    end
  end

  attr_reader :buffer, :futures, :ready
  def initialize(server,opts={})
    raise "can't run rpc client in the same thread as eventmachine" if EM.reactor_thread?
    self.extend(MonitorMixin)
    @server = server
    @seq = 0
    # queue is used be used to synchronize RPC
    # user thread and the AMQP eventmachine thread.
    @buffer = Queue.new
    @ready = {} # the ready results not yet waited
    @futures = {} # all futures not yet waited for.
    @reactor = Reactor.new(self)
    # Creates an exclusive queue to serve the RPC client.
    @client = @server.client(:key => "rpc.#{rand(999_999_999_999)}").
      queue(:exclusive => true).react(@reactor,opts)
  end

  def name
    @client.key
  end

  def call(method,data=nil,opts={})
    message_id = @seq.to_s # message gotta be unique for this RPC client.
    @client.call method, data, opts.merge(:message_id => message_id)
    @seq += 1
    @futures[message_id] = Future.new(self,message_id)
  end

  # the idea is to block on a synchronized queue
  # until we get the future we want.
  #
  # WARNING: blocks forever if the thread
  # calling wait is the same as the EventMachine
  # thread.
  #
  # It is safe (btw) to call wait within the
  # Server and Client reactor methods, because
  # they are invoked within their own EM
  # deferred threads (so does not block the main
  # EM reactor thread (which consumes the
  # messages from queue)).
  def wait(future,timeout=nil)
    return future.data if future.done? # future was waited before
    # we can have more fine grained synchronization later.
    ## easiest thing to do (later) is use threadsafe hash for @futures and @ready.
    ### But it's actually trickier than
    ### that. Before each @buffer.pop, a thread
    ### has to check again if it sees the result
    ### in @ready.
    self.synchronize do
      timer = nil
      if timeout
        timer = EM.add_timer(timeout) {
          @buffer << [:timeout,future.message_id]
        }
      end
      ready_future = nil
      if @ready.has_key? future.message_id
        @ready.delete future.message_id
        ready_future = future
      else
        while true
          header,data = @buffer.pop # synchronize. like erlang's mailbox select.
          if header == :timeout # timeout the future we are waiting for.
            message_id = data
            # if we got a timeout from previous wait. throw it away.
            next if future.message_id != message_id 
            future.timeout = true
            future.done!
            @futures.delete future.message_id
            return yield # return the value of timeout block
          end
          some_future = @futures[header.message_id]
          # If we didn't find the future among the
          # future, it must have timedout. Just
          # throw result away and keep processing.
          next unless some_future 
          some_future.header = header
          some_future.data = data
          if some_future == future
            # The future we are waiting for
            EM.cancel_timer(timer)
            ready_future = future
            break
          else
            # Ready, but we are not waiting for it. Save for later.
            @ready[some_future.message_id] = some_future
          end
        end
      end
      ready_future.done!
      @futures.delete ready_future.message_id
      return ready_future.data
    end
  end

  def waitall
    @futures.values.map { |k,v|
      wait(v)
    }
  end

  def inspect
    "#<#{self.class} #{self.name}>"
  end
end
