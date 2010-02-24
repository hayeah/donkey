require 'mq'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'monkey/mq'

class Donkey
  require "donkey/uuid"
  require 'donkey/rabbit'

  class Error < RuntimeError
  end
  
  class << self
    def default_settings
      {}
    end

    def default_channel
      @default_channel ||= Donkey::Channel.open(Donkey.default_settings)
      @default_channel
    end
  end

  attr_reader :id, :name, :channel, :reactor
  def initialize(name,reactor,channel=Donkey.default_channel)
    @id = Donkey::UUID.generate
    @reactor = reactor
    @name = name
    @channel = channel
  end

  attr_reader :public, :private
  def create
    @public  = Route::Public.declare(self)
    @private = Route::Private.declare(self)
  end

  def call(to,data,meta={})
    public.call(to,data,meta)
  end

  def cast(to,data,meta={})
    public.cast(to,data,meta)
  end

  def process(header,message)
    # TODO should use EM.defer
    @reactor.process(self,header,message)
  end

  def pop(opts={})
    public.pop(opts)
  end
end

class Donkey::Reactor < Struct.new(:donkey, :header, :message)
  def self.process(donkey,header,message)
    self.new(donkey,header,message).process
  end
  
  def process
    begin
      case message
      when Donkey::Message::Call
        on_call
      when Donkey::Message::Cast
        on_cast
      end
    rescue => error
      # FIXME what happens if it raises again here?
      ## Needs to do something, otherwise the thread would be killed.
      on_error(error)
    end
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

  def_delegators :@mq, :direct, :fanout, :topic, :queue
  
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

  class Cast < self
  end

  TAG_TO_CLASS = {
    "call" => Call,
    "cast" => Cast
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
      raise DecodeError
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
  
  def declare
    raise "abstract"
  end

  protected
  
  def publish
    raise "abstract"
  end

  class Public < self
    attr_reader :exchange, :queue
    def declare
      @exchange = channel.direct(donkey.name)
      @queue = channel.queue(donkey.name).bind(donkey.name,:key => "")
    end
    
    # gets one message delivered
    def pop(opts={})
      queue.pop(opts) do |header,payload|
        process(header,payload)
      end
    end

    def call(to,data,opts={})
      publish(to,Donkey::Message::Call.new(data),opts)
    end

    def cast(to,data,opts={})
      publish(to,Donkey::Message::Cast.new(data),opts)
    end

    private

    def process(header,payload)
      # FIXME decide what to do it it fails here. Right now, it just dies.
      donkey.process(header,Donkey::Message.decode(payload))
    end
    
    def publish(to,message,opts={})
      channel.publish(to,message.encode,opts.merge(:key => ""))
      message
    end
  end

  class Private < self
    def declare
      @id = donkey.id
      @exchange = channel.direct(donkey.name)
      @queue = channel.queue(@id,:auto_delete => true).bind(donkey.name,:key => @id)
    end

    def publish(message)
      channel.publish(message.to,message.payload,:key => message.id)
    end
  end
end
