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
    def build_callback_klass(callback)
      case callback
      when Proc
        Class.new &callback
      when Class
        callback
      when Module
        Class.new { include callback }
      end
    end
    
    def callback(info,payload)
      # method,data,meta
      if @callback_klass.respond_to? :version
        klass = @callback_klass.get_version(payload[:version])
      else
        klass = @callback_klass
      end
      obj = klass.new
      service = self
      obj.instance_variable_set("@__service__",service)
      obj.instance_variable_set("@__header__",info)
      obj.instance_variable_set("@__meta__",payload[:meta])
      class << obj
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
      #p [:call,payload]
      obj.send(payload[:method],
               payload[:data])
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
        @queue ||= MQ.queue(@key || self.name,opts)
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
      
      @callback_klass = build_callback_klass(callback)
      @ack = opts[:ack]
      # ensure queue is set
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        callback(info,payload)
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

    def client(opts={})
      ASS::Client.new(self,opts)
    end

    def client_name
      "#{self.exchange.name}---client"
    end

    def queue(opts={})
      unless @queue
        @queue ||= MQ.queue(self.name,opts)
        @queue.bind(self.exchange)
      end
      self
    end

    

    def react(callback=nil,opts=nil,&block)
      if block
        opts = callback
        callback = block
      end
      opts = {} if opts.nil?
      
      @callback_klass = build_callback_klass(callback)
      @ack = opts[:ack]
      self.queue unless @queue
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        #p [info,info.reply_to,payload]
        data2 = callback(info,payload)
        payload2 = payload.merge :data => data2
        # the client MUST exist, otherwise it's an error.
        ## FIXME it's bad if the server dies b/c the client isn't there.
        MQ.direct(info.reply_to,:passive => true).
          publish(::Marshal.dump(payload2),
                  :routing_key => info.routing_key) if info.reply_to
        info.ack if @ack
      end
      self
    end
  end

  class Peeper
    def initialize(exchange,callback)
      # create a temporary queue that binds to an exchange
    end
  end
end
