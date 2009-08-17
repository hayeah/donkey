require 'mq'

# TODO convert to JSON msgs
module ASS
  
  attr_reader :server_exchange

  # non-destructive get. Fail if server's not started.
  def self.get(name)
    ASS::Server.new(name,:passive => true)
  end

  def self.new(name,opts={})
    ASS::Server.new(name)
  end
  
  module Callback
    module MagicMethods
      def header
        @__header__
      end
      
      def meta
        @__meta__
      end
      
      def service
        @__service__
      end
      
      def call(method,data=nil,meta=nil,opts={})
        @__service__.call(method,data,meta,opts)
      end
    end

    # called to initiate a callback
    def build_callback(callback)
      c = case callback
          when Proc
            Class.new &callback
          when Class
            callback
          when Module
            Class.new { include callback }
          when Object
            callback # use singleton objcet as callback
          end
      case c
      when Class
        c.instance_eval { include MagicMethods }
      else
        c.extend MagicMethods
      end
      c
    end

    # called for each request
    def prepare_callback(callback,info,payload)
      # method,data,meta
      if callback.is_a? Class
        if callback.respond_to? :version
          klass = callback.get_version(payload[:version])
        else
          klass = callback
        end
        obj = klass.new
      else
        obj = callback
      end
      obj.instance_variable_set("@__service__",self)
      obj.instance_variable_set("@__header__",info)
      obj.instance_variable_set("@__meta__",payload[:meta])
      #p [:call,payload]
      obj
    end
  end

  class Server
    include Callback

    def initialize(name,opts={})
      @server_exchange = MQ.fanout(name,opts)
    end

    def name
      self.exchange.name
    end
    
    def exchange
      @server_exchange
    end

    # takes options available to MQ::Exchange
    def client(opts={})
      ASS::Client.new(self,opts)
    end

    def client_name
      "#{self.exchange.name}--"
    end

    # takes options available to MQ::Queue# takes options available to MQ::Queue#subscribe
    def rpc(opts={})
      ASS::RPC.new(self,opts)
    end

    def queue(opts={})
      unless @queue
        @queue ||= MQ.queue(self.name,opts)
        @queue.bind(self.exchange)
      end
      self
    end

    # takes options available to MQ::Queue# takes options available to MQ::Queue#subscribe
    def react(callback=nil,opts=nil,&block)
      if block
        opts = callback
        callback = block
      end
      opts = {} if opts.nil?
      
      @callback = build_callback(callback)
      @ack = opts[:ack]
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        #p [info,info.reply_to,payload]
        obj = prepare_callback(@callback,info,payload)
        data2 = obj.send(payload[:method],payload[:data])
        payload2 = payload.merge :data => data2
        # the client MUST exist, otherwise it's an error.
        ## FIXME it's bad if the server dies b/c
        ## the client isn't there. It's bad that
        ## this can cause the server to fail.
        MQ.direct(info.reply_to,:passive => true).
          publish(::Marshal.dump(payload2),
                  :routing_key => info.routing_key,
                  :message_id => info.message_id) if info.reply_to
        info.ack if @ack
      end
      self
    end

    def inspect
      "#<#{self.class} #{self.name}>"
    end
  end

  class Client
    include Callback

    # takes options available to MQ::Exchange
    def initialize(server,opts={})
      @server = server
      # the routing key is also used as the name of the client
      @key = opts.delete :key
      @key = @key.to_s if @key
      @client_exchange = MQ.direct @server.client_name, opts
    end

    def name
      self.exchange.name
    end

    def exchange
      @client_exchange
    end

    # takes options available to MQ::Queue
    def queue(opts={})
      unless @queue
        # if key is not given, the queue name is
        # the same as the exchange name.
        @queue ||= MQ.queue("#{self.name}#{@key}",opts)
        @queue.bind(self.exchange,:routing_key => @key || self.name)
      end
      self # return self to allow chaining
    end

    # takes options available to MQ::Queue#subscribe
    def react(callback=nil,opts=nil,&block)
      if block
        opts = callback
        callback = block
      end
      opts = {} if opts.nil?

      @callback = build_callback(callback)
      @ack = opts[:ack]
      # ensure queue is set
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        obj = prepare_callback(@callback,info,payload)
        obj.send(payload[:method],payload[:data])
        info.ack if @ack
      end
      self
    end

    # note that we can redirect the result to some
    # place else by setting :key and :reply_to
    def call(method,data=nil,meta=nil,opts={})
      # opts passed to publish
      # if no routing key is given, use receiver's name as the routing key.
      version = @klass.version  if @klass.respond_to? :version
      payload = {
        :method => method,
        :data => data,
        :meta => meta,
        :version => version
      }

      @server.exchange.publish Marshal.dump(payload), {
        # opts[:routing_key] will override :key in MQ::Exchange#publish
        :key => (@key ? @key : self.name),
        :reply_to => self.name
      }.merge(opts)
    end
    
    # for casting, just null the reply_to field, so server doesn't respond.
    def cast(method,data=nil,meta=nil,opts={})
      self.call(method,data,meta,opts.merge({:reply_to => nil}))
    end

    def inspect
      "#<#{self.class} #{self.name}>"
    end
  end

  # assumes server initializes it with an exclusive and auto_delete queue.
  # TODO timeout
  class RPC
    require 'thread'

    # i don't want deferrable. I want actual blockage when waiting.
    ## subscribe prolly run in a different thread.
    # hmmm. I guess deferrable is a better idea.
    class Future
      attr_reader :message_id
      attr_accessor :header, :data, :meta, :timeout
      def initialize(rpc,message_id)
        @message_id = message_id
        @rpc = rpc
        @timeout = false
        @done = false
      end
      
      def wait(timeout=nil,&block)
        # TODO timeout with eventmachine
        @rpc.wait(self,timeout,&block) # synchronous call that will block
        # EM.cancel_timer(ticket)
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
        @rpc.buffer << [header,data,meta]
      end
    end

    attr_reader :buffer, :futures, :ready
    def initialize(server,opts={})
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

    def call(method,data,meta=nil,opts={})
      message_id = @seq.to_s # message gotta be unique for this RPC client.
      @client.call method, data, meta, opts.merge(:message_id => message_id)
      @seq += 1
      @futures[message_id] = Future.new(self,message_id)
    end

    # the idea is to block on a synchronized queue
    # until we get the future we want.
    #
    # WARNING: blocks forever if the thread
    # calling wait is the same as the EventMachine
    # thread.
    def wait(future,timeout=nil)
      return future.data if future.done? # future was waited before
      timer = nil
      if timeout
        timer = EM.add_timer(timeout) {
          @buffer << [:timeout,future.message_id,nil]
        }
      end
      ready_future = nil
      if @ready.has_key? future.message_id
        @ready.delete future.message_id
        ready_future = future
      else
        while true
          header,data,meta = data = @buffer.pop # synchronize. like erlang's mailbox select.
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
          some_future.meta = meta
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

    def waitall
      @futures.values.map { |k,v|
        wait(v)
      }
    end

    def inspect
      "#<#{self.class} #{self.name}>"
    end
  end
end
