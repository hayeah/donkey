require 'mq'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'monkey/mq'

class Donkey
  require "donkey/uuid"
  require 'donkey/rabbit'

  class Error < RuntimeError
  end

  class BadReceipt < Error
  end

  class AlreadySubscribed < Error
  end

  class NotSubscribed < Error
  end
  
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

  attr_reader :id, :name, :channel, :reactor, :waiter_map, :ticketer
  def initialize(name,reactor,channel=Donkey.channel)
    @id = Donkey::UUID.generate
    @reactor = reactor
    @name = name
    @channel = channel
    @waiter_map = Donkey::WaiterMap.new
    @ticketer = Donkey::Ticketer.new
  end

  attr_reader :public, :private
  def create
    @public  = Route::Public.declare(self)
    @private = Route::Private.declare(self)
    private.subscribe
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
  def reply(header,message,result,opts={})
    # message not used
    private.reply(header.reply_to,
                  result,
                  header.message_id,
                  opts)
  end

  def ack(header)
    header.ack
  end
  
  def wait(*receipts,&block)
    raise BadReceipt if receipts.any? { |receipt| receipt.donkey != self }
    keys = receipts.map(&:key)
    Donkey::Waiter.new(waiter_map,*keys,&block)
  end

  # only Reactor should call this
  def signal(key,value)
    waiter_map.signal(key,value)
  end

  # only Reactor should call this
  def process(header,message,ack)
    @reactor.process(self,header,message,ack)
  end

  def pop(opts={},&on_empty)
    raise Donkey::AlreadySubscribed if subscribed?
    public.pop(opts,&on_empty)
  end

  def subscribe(opts={})
    raise Donkey::AlreadySubscribed if subscribed?
    public.subscribe(opts)
    @subscribed = true
  end

  def unsubscribe(opts={})
    raise Donkey::NotSubscribed if not subscribed?
    public.unsubscribe
    @subscribed = false
  end

  def subscribed?
    @subscribed == true
  end
end

class Donkey::Receipt < Struct.new(:donkey,:key)
  def wait(&block)
    donkey.wait(self,&block)
  end
end

class Donkey::Ticketer
  # TODO synchronize?
  def initialize
    # @mutex = Mutex.new
    @counter = 0
  end
  
  def next
    @counter += 1
    @counter.to_s
  end
end

class Donkey::Waiter
  class Error < Donkey::Error
  end
  class NotReceived < Error
  end

  class AlreadySignaled < Error
  end

  class TimeoutAlreadySet < Error
  end
  
  attr_reader :pending, :received
  attr_reader :success_callback
  def initialize(waiter_map,*keys,&block)
    @success_callback = block
    @keys = keys
    @pending  = Set.new(@keys)
    @received = {} # map(key => value)
    @waiter_map = waiter_map
    @waiter_map.register(self,*keys)
  end

  attr_reader :timeout_callback, :timer
  def timeout(time,&block)
    raise TimeoutAlreadySet,self if @timer
    @timer = EM::Timer.new(time) {on_timeout}
    @timeout_callback = block
    self
  end

  def ready?
    @pending.empty?
  end

  def received?(key)
    @received.has_key?(key)
  end

  def value(key)
    if received?(key)
      @received[key]
    else
      raise NotReceived, key
    end
  end

  def values
    @keys.map { |key| value(key) }
  end

  def signal(key,value)
    # double signaling should not happen..?
    raise AlreadySignaled, key if received?(key)
    @pending.delete(key)
    @received[key] = value
    on_success if @pending.empty?
  end

  def status
    @status
  end
  
  def done?
    not @status.nil?
  end

  def success?
    status == :success
  end

  def timeout?
    status == :timeout
  end

  private

  def complete(status,&block)
    return if done?
    @status = status
    @waiter_map.unregister(self,*@keys)
    timer.cancel if timer
    # NB to avoid timing issues, better to clean
    # up, then to call the success callback
    block.call
  end
  
  def status=(status)
    @status = status
  end
  
  def on_timeout
    complete(:timeout) do
      timeout_callback.call(self)
    end
  end

  def on_success
    complete(:success) do
      success_callback.call(*values)
    end
  end
end

class Donkey::WaiterMap
  require 'set'

  class RepeatedCheckin < Donkey::Error
  end

  attr_reader :map
  def initialize
    @map = Hash.new { |h,k| h[k] = Set.new }
  end

  def register(waiter,*keys)
    keys.each do |key|
      @map[key] << waiter
    end
  end

  # waiter is responsible of unregistering itself
  def unregister(waiter,*keys)
    keys.each do |key|
      waiters = @map[key].delete(waiter)
      @map.delete(key) if waiters.empty?
    end
  end

  def signal(key,value)
    waiters_of(key).each { |waiter| waiter.signal(key,value) }
  end

  def waiters_of(key)
    @map[key]
  end
end

class Donkey::Reactor
  class NoAckNeeded < Donkey::Error
  end
  
  def self.process(donkey,header,message,ack)
    self.new(donkey,header,message,ack).process
  end

  attr_reader :donkey, :header, :message, :ack
  def initialize(donkey,header,message,ack)
    @donkey = donkey
    @header = header
    @message = message
    @ack = ack
  end

  def ack?
    @ack == true
  end
  
  def process
    begin
      case message
      when Donkey::Message::Call
        on_call
      when Donkey::Message::Cast
        on_cast
      when Donkey::Message::Back
        donkey.signal(header.message_id,message.data)
      end
    rescue => error
      begin
        on_error(error)
      rescue => error2
        die(error)
      end
    end
  end

  def die(error)
    # TODO wants to enable user definable logging here
    $stderr.puts error.to_s
    $stderr.puts error.backtrace
    Donkey.stop
  end

  def reply(result,opts={})
    raise Donkey::Error, "can only reply to a call" unless Donkey::Message::Call === message
    raise Donkey::Error, "can only reply once" if @replied
    @replied = true
    donkey.reply(header,message,result,opts)
  end

  def ack
    raise NoAckNeeded unless ack?
    donkey.ack(header)
  end

  def replied?
    @replied == true
  end

  def on_call
    raise "abstract"
  end

  def on_cast
    raise "abstract"
  end

  def on_error(error)
    raise error
  end
end

class Donkey::Channel
  require 'forwardable'
  extend Forwardable

  def_delegators :@mq, :direct, :fanout, :topic, :queue, :publish
  
  def self.open(settings={})
    self.new(settings)
  end

  def self.default_settings
    AMQP.settings
  end

  def self.ensure_eventmachine
    unless EM.reactor_running?
      t = Thread.new { EM.run }
      t.abort_on_exception = true
    end
  end

  attr_reader :settings, :mq, :connection
  def initialize(settings={})
    self.class.ensure_eventmachine
    @settings = self.class.default_settings.merge(settings)
    @connection = AMQP.connect(@settings)
    @mq = MQ.new(@connection)
    @connection.connection_status { |sym|
      case sym
      when :connected
        self.on_connect
      when :disconnected
        self.on_disconnect
      end
    }
  end
  
  def on_connect(&block)
    if block
      # setting on_connect callback
      @on_connect = block
    else
      # eventmahcine invoking callback
      @on_connect.call if @on_connect
    end
  end

  # AMQP gem automatically reconnects. this
  # callback should be used for side-effect only,
  # or to drastic measures like exit the process.
  #
  # Upon reconnection, all the entities this
  # connection knows about would be reset &
  # redeclared.
  def on_disconnect(&block)
    if block
      # setting on_connect callback
      @on_disconnect = block
    else
      # eventmahcine invoking callback
      @on_disconnect.call if @on_disconnect
    end
  end
end

class Donkey::Message
  require 'bert'

  class DecodeError < Donkey::Error
  end

  class Call < self
  end

  class Back < self
  end
  
  class Cast < self
  end

  TAG_TO_CLASS = {
    "call" => Call,
    "cast" => Cast,
    "back" => Back
  }
  CLASS_TO_TAG = TAG_TO_CLASS.inject({}) do |h,(k,v)|
    h[v] = k
    h
  end

  def self.decode(payload)
    begin
      tag, data = BERT.decode(payload)
      tag_to_class(tag).new(data)
    rescue
      raise DecodeError, payload
    end
  end

  def self.tag_to_class(tag)
    TAG_TO_CLASS[tag] || raise("no class for tag: #{tag}")
  end

  def self.class_to_tag(klass)
    CLASS_TO_TAG[klass] || raise("no tag for class: #{self}")
  end

  def self.tag
    @tag ||= class_to_tag(self)
    @tag
  end

  def tag
    self.class.tag
  end

  attr_reader :data
  def initialize(data)
    @data = data
  end

  def tagged_data
    [tag,@data]
  end
  
  def encode
    BERT.encode(self.tagged_data)
  end
end

class Donkey::Route
  attr_reader :donkey
  def self.declare(donkey)
    route = self.new(donkey)
    route.declare
    route
  end
  
  def initialize(donkey)
    @donkey = donkey
  end

  def channel
    donkey.channel
  end

  attr_reader :exchange, :queue
  def declare
    raise "abstract"
    # must set @exchange and @queue
  end

  #gets one message delivered
  def pop(opts={},&on_empty)
    ack = (opts[:ack] == true)
    queue.pop(opts) do |header,payload|
      # NB: when the queue is empty, header is an
      # MQ::Header that prints "nil". very
      # confusing. payload is just a regular nil.
      if payload.nil?
        # this happens when the queue is empty
        on_empty.call if on_empty
      else
        process(header,payload,ack)
      end
    end
  end
  
  def subscribe(opts={})
    ack = (opts[:ack] == true)
    queue.subscribe(opts) do |header,payload|
      process(header,payload,ack)
    end
  end

  def unsubscribe(opts={})
    queue.unsubscribe(opts)
  end

  protected

  def publish(to,message,opts={})
    channel.publish(to,message.encode,opts)
    message
  end
  
  def process(header,payload,ack)
    donkey.process(header,Donkey::Message.decode(payload),ack)
  end
  
  class Public < self
    attr_reader :exchange, :queue
    def declare
      @exchange = channel.direct(donkey.name)
      @queue = channel.queue(donkey.name).bind(donkey.name,:key => "")
    end

    def call(to,data,tag,opts={})
      publish(to,
              Donkey::Message::Call.new(data),
              opts.merge(:reply_to => "#{donkey.name}##{donkey.id}",
                         :message_id => tag.to_s))
    end

    def cast(to,data,opts={})
      publish(to,
              Donkey::Message::Cast.new(data),
              opts)
    end
  end

  class Private < self
    def declare
      @id = donkey.id
      @exchange = channel.direct(donkey.name)
      @queue = channel.queue(@id,:auto_delete => true).bind(donkey.name,:key => @id)
    end

    def reply(reply_to,data,tag,opts={})
      reply_to.match(/^(.+)#(.+)$/)
      donkey_name = $1
      donkey_id = $2
      publish(donkey_name,
              Donkey::Message::Back.new(data),
              opts.merge({ :message_id => tag.to_s,
                           :routing_key => donkey_id}))
    end
  end
end
