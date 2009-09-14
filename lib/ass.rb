$:.unshift File.expand_path(File.dirname(File.expand_path(__FILE__)))
require 'mq'
require 'ass/amqp' # monkey patch stolen from nanite.
# TODO a way to specify serializer (json, marshal...)
module ASS

  #MQ = nil
  def self.start(settings={})
    # ASS and its worker threads should share the same MQ instance.
    raise "should have one ASS per process" if @started
    @started = true
    EM.run {
      @mq = ::MQ.new(AMQP.start(settings))
      self.const_set("MQ",@mq)
      yield if block_given?
    }
  end

  def self.MQ
    @mq
  end

  # non-destructive get. Fail if server's not started.
  def self.get(name)
    ASS::Server.new(name,:no_declare => true)
  end

  def self.new(name,opts={})
    ASS::Server.new(name)
  end

  def self.client(name,opts={})
    ASS.get(name).client(opts)
  end

  def self.topic(name,opts={})
    ASS::Topic.new(name,opts)
  end

  def self.rpc(name,opts={})
    self.get(name).rpc(opts)
  end

  # sometime you just want to respond to the reply_to
  # of a message without anything else.
  def self.call(name,data=nil,opts={})
    MQ.direct(name,:no_declare => true).publish(::Marshal.dump(data),opts)
  end

  def self.peep(server_name,callback=nil,&block)
    callback = block if callback.nil?
    callback = Module.new {
      def server(*args)
        p [:server,args]
      end

      def client(*args)
        p [:client,args]
      end
    }
    ASS::Peeper.new(server_name,callback)
  end
  
  module Callback
    module MagicMethods
      def requeue
        throw(:__ass_requeue)
      end
      
      def discard
        throw(:__ass_discard)
      end
      
      def header
        @__header__
      end

      def service
        @__service__
      end
      
      def call(method,data=nil,opts={})
        @__service__.call(method,data,opts)
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
      # method,data
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

      # second call would just swap out the callback.
      @callback = build_callback(callback)

      return(self) if @subscribed
      @subscribed = true
      @ack = opts[:ack]
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        operation = proc {
          begin
            payload = ::Marshal.load(payload)
            obj = prepare_callback(@callback,info,payload)
            
            not_discarded = false
            not_requeued = false
            payload2 = nil
            catch(:__ass_discard) do
              catch(:__ass_requeue) do
                data2 = obj.send(payload[:method],payload[:data])
                payload2 = payload.merge :data => data2
                not_requeued = true
              end
              not_discarded = true
            end
            if not_discarded && not_requeued
              [:ok,payload2]
            elsif not_discarded == false
              [:discarded]
            elsif not_requeued == false
              [:requeued,payload] # requeue original payload
            end
          rescue
            [:error,$!]
          end
        }
        done = proc { |result|
          # the client MUST exist, otherwise it's an error.
          ## FIXME it's bad if the server dies b/c
          ## the client isn't there. It's bad that
          ## this can cause the server to fail.
          ##
          ## I am actually not sure what happens if
          ## message is unroutable. I think it's
          ## just silently dropped unless the
          ## mandatory option is given.
          case status = result[0]
          when :ok
            # respond back to client
            payload = result[1]
            
            ASS.call(info.reply_to, payload,
                     :routing_key => info.routing_key,
                     :message_id => info.message_id) if info.reply_to
            info.ack if @ack
          when :requeued
            # resend the same message
            payload = result[1]
            #p [:requeue,self,payload,info]
            ASS.call(self.name,payload,{
                       :reply_to => info.reply_to,
                       :routing_key => info.routing_key,
                       :message_id => info.message_id
                     })
            info.ack if @ack
          when :discarded
            # no response back to client
            info.ack if @ack
          when :error
            # programmatic error. don't ack
            e = result[1]
            p e
            puts e.backtrace
            EM.stop_event_loop
            # don't ack.
          end
          
        }
        EM.defer operation, done
      end
      self
    end

    def inspect
      "#<#{self.class} #{self.name}>"
    end
  end

  class Client
    include Callback

    attr_reader :key
    # takes options available to MQ::Exchange
    def initialize(server,opts={})
      @server = server
      # the routing key is also used as the name of the client
      key = opts.delete :key
      @client_exchange = MQ.direct @server.client_name, opts
      @key = key ? key.to_s : @server.client_name
    end

    def rpc(opts={})
      @rpc ||= @server.rpc(opts)
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
        @queue.bind(self.exchange,:routing_key => self.key)
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

      # second call would just swap out the callback.
      @callback = build_callback(callback)

      return(self) if @subscribed
      @subscribed = true
      @ack = opts[:ack]
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        operation = proc {
          begin
            payload2 = ::Marshal.load(payload)
            obj = prepare_callback(@callback,info,payload2)
            obj.send(payload2[:method],payload2[:data])
            [:ok]
          rescue
            [:error,$!]
          end
        }
        done = proc { |result|
          # not actually doing anything with result
          info.ack if @ack
          case result[0]
          when :ok
            # do nothing
          when :error
            e = result[1]
            p e
            puts e.backtrace
            # unhandled error should break ASS
            EM.stop_event_loop
          end
        }
        EM.defer operation, done
      end
      self
    end

    # we can redirect the result to some other
    # place by setting a combination of
    # :routing_key (alias :key)
    # :reply_to
    def call(method,data=nil,opts={})
      # opts passed to publish
      payload = {
        :method => method,
        :data => data,
      }
      # if no routing key is given, use receiver's name as the routing key.
      # opts[:routing_key] will override :key in MQ::Exchange#publish
      ASS.call(@server.exchange.name,payload, {
                 :key => self.key,
                 :reply_to => self.name}.merge(opts))
    end

    # for casting, just null the reply_to field, so server doesn't respond.
    def cast(method,data=nil,opts={})
      self.call(method,data,opts.merge({:reply_to => nil}))
    end
    
    def inspect
      "#<#{self.class} #{self.name}>"
    end
  end

  # assumes server initializes it with an exclusive and auto_delete queue.
  class RPC
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

  # TODO should prolly have the option of using
  # non auto-delete queues. This would be useful
  # for logger. Maybe if a peeper name is given,
  # then create queues with options.
  class Peeper
    include Callback
    attr_reader :server_name
    def initialize(server_name,callback)
      @server_name = server_name
      @clients = {}
      @callback = build_callback(callback)
      
      uid = "#{@server_name}.peeper.#{rand 999_999_999_999}"
      q = MQ.queue uid, :auto_delete => true
      q.bind(@server_name) # messages to the server would be duplicated here.
      q.subscribe { |info,payload|
        payload = ::Marshal.load(payload)
        # sets context, but doesn't make the call
        obj = prepare_callback(@callback,info,payload)
        # there is a specific method we want to call.
        obj.server(payload[:method],payload[:data])

        # bind to peep client message queue if we've not seen it before.
        unless @clients.has_key? info.routing_key
          @clients[info.routing_key] = true
          client_q = MQ.queue "#{uid}--#{info.routing_key}",
           :auto_delete => true
          # messages to the client would be duplicated here.
          client_q.bind("#{server_name}--", :routing_key => info.routing_key) 
          client_q.subscribe { |info,payload|
            payload = ::Marshal.load(payload)
            obj = prepare_callback(@callback,info,payload)
            obj.client(payload[:method],payload[:data])
          }
        end
      }
    end
  end

  class Topic
    def initialize(name,opts={})
      @exchange = MQ.topic(name,opts)
    end

    def publish(key,payload,opts={})
      @exchange.publish(::Marshal.dump(payload),opts.merge(:routing_key => key))
    end

    def subscribe(matcher,opts={},&block)
      ack = opts.delete(:ack)
      uid = "#{@exchange.name}.topic.#{rand 999_999_999_999}"
      q = MQ.queue(uid,opts)
      q.bind(@exchange.name,:key => matcher)
      q.subscribe(:ack => ack) { |info,payload|
        payload = ::Marshal.load(payload)
        if block.arity == 2
          block.call(info,payload)
        else
          block.call(payload)
        end
      }
      q
    end
  end

end
