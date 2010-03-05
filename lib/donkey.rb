require 'mq'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

# monkey patching amqp for publishing without creating an exchange object
require 'donkey/mq'

class Donkey
  class Error < RuntimeError
  end

  class BadReceipt < Error
  end

  class NoBlockGiven < Error
  end

  %w(uuid rabbit
channel route
receipt ticketer
message 
signal_map
signaler
waiter
reactor actor).each { |file|
    require "donkey/#{file}"
  }
  
  class << self
    def topic(name,opts={})
      Donkey.channel.topic(name,opts)
    end
  end

  attr_reader :id, :name, :channel, :reactor, :signal_map, :ticketer
  def initialize(name,reactor)
    @id = Donkey::UUID.generate
    @reactor = reactor
    @name = name
    @channel = Donkey.channel
    @signal_map = Donkey::SignalMap.new
    @ticketer = Donkey::Ticketer.new
  end

  attr_reader :public, :private, :topic, :fanout
  def create
    @public  = Route::Public.declare(self)
    @private = Route::Private.declare(self)
    @topic = Route::Topic.declare(self)
    @fanout = Route::Fanout.declare(self)
  end

  def call(to,data,opts={})
    tag = opts.delete(:tag) || ticketer.next
    public.call(to,data,tag,opts)
    Donkey::Receipt.new(self,tag)
  end

  def cast(to,data,opts={})
    public.cast(to,data,opts)
  end

  # only Reactor should call this (by magic...)
  def back(header,message,result,opts={})
    # message not used
    private.back(header.reply_to,
                 result,
                 header.message_id,
                 opts)
  end

  def bback(header,message,result,opts={})
    # message not used
    fanout.bback(header.reply_to,
                 result,
                 header.message_id,
                 opts)
  end

  def bcall(to,data,opts={},&block)
    raise NoBlockGiven unless block
    tag = opts.delete(:tag) || ticketer.next
    fanout.bcall(to,data,tag,opts)
    Donkey::Signaler.new(signal_map,tag,&block)
  end

  def bcast(to,data,opts={})
    fanout.bcast(to,data,opts)
  end
  
  def event(name,key,data,opts={})
    topic.event(name,key,data,opts)
  end

  def listen(name,key)
    topic.listen(name,key)
  end

  def unlisten(name,key)
    topic.unlisten(name,key)
  end

  def ack(header)
    header.ack
  end
  
  def wait(*receipts,&block)
    raise NoBlockGiven if block.nil?
    raise BadReceipt if receipts.any? { |receipt| receipt.donkey != self }
    keys = receipts.map(&:key)
    Donkey::Waiter.new(signal_map,*keys,&block)
  end

  # only Reactor should call this
  def signal(key,value)
    signal_map.signal(key,value)
  end

  # only Reactor should call this
  def process(header,message,ack)
    @reactor.process(self,header,message,ack)
  end
end

class Donkey
  class << self
    # FIXME hmmm... this would render all the
    # previously created objects useless. So for
    # example Donkey.default_channel caches a
    # default channel. That would break.
    #
    # FIXME uhhhhhh... this could be called from with eventmachine thread when reactor dies
    def stop
      if EM.reactor_running?
        # wait for EventMachine cleanup
        EM.stop_event_loop
        t = EM.instance_variable_get(:@reactor_thread)
        t.join
      end
      # clean up AMQP
      Thread.current[:mq] = nil
      AMQP.instance_variable_set('@conn', nil)
      # FIXME clean up donkey
      @default_channel = nil
    end

    attr_accessor :default_settings
    Donkey.default_settings = AMQP.settings.merge(:logging => ENV["trace"])

    # create donkey objects with a channel
    def with(arg)
      case arg
      when Donkey::Channel
        c = arg
      when Hash
        c = Donkey::Channel.open(arg)
      else
        raise Error, "expects a channel"
      end
      begin
        old_with_channel = @with_channel
        @with_channel = c
        yield
      ensure
        @with_channel = old_with_channel
      end
    end
    
    def channel
      @with_channel || default_channel
    end
    
    def default_channel
      @default_channel ||= Donkey::Channel.open(Donkey.default_settings)
      @default_channel
    end
  end
end
