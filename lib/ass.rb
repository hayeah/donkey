require 'mq'
class ASS
  
  attr_reader :server_exchange

  def self.declare(server_exchange)
    self.new([server_exchange,{:passive => true}])
  end
  
  # uh... we'll assume that the exchanges are all direct exchanges.
  def initialize(server_exchange)
    @server_exchange = get_exchange(server_exchange)
  end

  def client(client_exchange,*args)
    @client_exchange ||= get_exchange(client_exchange)
    q = get_queue(@client_exchange,*args) 
    Client.new(@server_exchange,@client_exchange,q)
  end

  def server(*args)
    Server.new(@server_exchange,get_queue(@server_exchange,*args))
  end

  def get_exchange(arg)
    case arg
    when Array
      exchanges = exchange[0]
      opts = exchange[1]
    else
      exchange = arg
      opts = nil
    end
    opts = {} if opts.nil?
    exchange = exchange.is_a?(MQ::Exchange) ? exchange : MQ.direct(exchange,opts)
    raise "accepts only direct exchanges" unless exchange.type == :direct
    exchange
  end

  # can specify a key to create a queue for that subdomain
  def get_queue(exchange,*args)
    case args[0]
    when Hash
      key = nil
      opts = args[0]
    when String
      key = args[0]
      opts = args[1]
    end
    opts = {} if opts.nil?
    if key
      name = "#{exchange.name}--#{key}"
      q = MQ.queue(name,opts)
      q.bind(exchange,{ :routing_key => key})
    else
      q = MQ.queue(exchange.name,opts)
      q.bind(exchange,{ :routing_key => exchange.name })
    end
    q
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
    def initialize(server_exchange,client_exchange,queue)
      @server_exchange = server_exchange
      @client_exchange = client_exchange
      @queue = queue
    end
    
    def react(callback=nil,opts=nil,&block)
      if block
        opts = callback
        callback = block
      end
      opts = {} if opts.nil?
      
      @callback_klass = build_callback_klass(callback)
      @ack = opts[:ack]
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        callback(info,payload)
        info.ack if @ack
      end
      self
    end
    
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

      # set it up s.t. server would respond to
      # private queue if key is given, otherwise
      # the server would respond to public queue.
      key = opts.delete(:key)
      @server_exchange.publish Marshal.dump(payload), {
        :key => (key ? key : @server_exchange.name),
        :reply_to => @client_exchange.name
      }.merge(opts)
    end

    # for casting, just null the reply_to field, so server doesn't respond.
    def cast(method,data=nil,meta=nil,opts={})
      self.call(method,data,meta,opts.merge({:reply_to => nil}))
    end

    
  end

  class Server
    include Callback

    def initialize(server_exchange,q)
      @queue = q
      @server_exchange = server_exchange
    end

    attr_reader :queue
    def exchange
      @server_exchange
    end

    def react(callback=nil,opts=nil,&block)
      if block
        opts = callback
        callback = block
      end
      opts = {} if opts.nil?
      
      @callback_klass = build_callback_klass(callback)
      @ack = opts[:ack]
      @queue.subscribe(opts) do |info,payload|
        payload = ::Marshal.load(payload)
        #p [info,info.reply_to,payload]
        data2 = callback(info,payload)
        payload2 = payload.merge :data => data2
        if info.routing_key == @server_exchange.name
          # addressed to the server's public
          # queue, respond to the routing_key of
          # the client's public queue.
          key = info.reply_to
        else
          # addressed to the private queue
          key = info.routing_key
        end
        MQ.direct(info.reply_to).publish(::Marshal.dump(payload2),:routing_key => key) if info.reply_to
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
