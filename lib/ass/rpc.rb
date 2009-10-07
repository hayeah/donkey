# A RPC client is a transient entity that dies
# with the process that created it. Its purpose
# is only to provide a synchronized interface to
# the asynchronous services.
require 'thread'
require 'monitor'
class ASS::RPC
  # stolen from nanite
  def self.random_id
      values = [
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x1000000),
        rand(0x1000000),
      ]
      "%04x%04x%04x%04x%04x%06x%06x" % values
  end
  
  class Future
    # TODO set meta
    attr_reader :message_id
    attr_accessor :header, :data, :method, :meta
    attr_accessor :timeout
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

  attr_reader :name
  attr_reader :buffer, :futures, :ready
  def initialize(opts={})
    raise "can't run rpc client in the same thread as eventmachine" if EM.reactor_thread?
    self.extend(MonitorMixin)
    @seq = 0
    # queue is used be used to synchronize RPC
    # user thread and the AMQP eventmachine thread.
    @buffer = Queue.new
    @ready = {} # the ready results not yet waited
    @futures = {} # all futures not yet waited for.
    # Creates an exclusive queue to serve the RPC client.
    @rpc_id = ASS::RPC.random_id.to_s
    buffer = @buffer # closure binding for reactor
    exchange = ASS.mq.direct("__rpc__")
    queue = ASS.mq.queue("__rpc__#{@rpc_id}",
                         :exclusive => true,:auto_delete => true)
    queue.bind("__rpc__",:routing_key => @rpc_id)
    queue.subscribe { |header,payload|
      payload = ::Marshal.load(payload)
      buffer << [header,payload]
    }
  end

  def call(server_name,method,data=nil,opts={},meta=nil)
    self.synchronize do
      message_id = @seq.to_s # message gotta be unique for this RPC client.
      # by default route message to the exchange @name@, with routing key @name@
      ASS.call(server_name,
               method,
               data,
               # can't override these options
               opts.merge(:message_id => message_id,
                          :reply_to => "__rpc__",
                          :key => @rpc_id),
               meta)
      @seq += 1
      @futures[message_id] = Future.new(self,message_id)
    end
  end

  # the idea is to block on a synchronized queue
  # until we get the future we want.
  #
  # WARNING: blocks forever if the thread
  # calling wait is the same as the EventMachine
  # thread.
  #
  # It is safe (btw) to use the RPC client within
  # an ASS server/actor, because the wait is in an
  # EM worker thread, rather than the EM thread
  # itself. The EM thread is still free to process
  # the queue. CAVEAT: you could run out of EM
  # worker threads.
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
          header,payload = @buffer.pop # synchronize. like erlang's mailbox select.
          if header == :timeout # timeout the future we are waiting for.
            message_id = payload
            # if we got a timeout from previous wait. throw it away.
            next if future.message_id != message_id 
            future.timeout = true
            future.done!
            @futures.delete future.message_id
            return yield # return the value of timeout block
          end
          data = payload[:data]
          some_future = @futures[header.message_id]
          # If we didn't find the future among the
          # future, it must have timedout. Just
          # throw result away and keep processing.
          next unless some_future
          some_future.timeout = false
          some_future.header = header
          some_future.data = data
          some_future.method = payload[:method]
          some_future.meta = payload[:meta]
          if some_future == future
            # The future we are waiting for
            EM.cancel_timer(timer) if timer
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
