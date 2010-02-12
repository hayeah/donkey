require 'mq'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'monkey/mq'

class Donkey
  require "donkey/uuid"
  class << self
    def channel
      @channel ||= Donkey::Channel.open
      @channel
    end
  end

  attr_reader :id, :name, :channel
  def initialize(name)
    @id = Donkey::UUID.generate
    @name = name
    @channel = Donkey.channel
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

  def pop
    public.pop
  end
end

module Donkey::Rabbit
  extend self

  def vhosts
    `rabbitmqctl list_vhosts`.split("\n")[1..-2]
  end

  def bindings(vhost=nil)
    query("list_bindings",%w(exchange_name queue_name routing_key arguments),vhost)
  end
  
  def queues(vhost=nil)
    query("list_queues",%w(name durable auto_delete arguments messages_ready messages_unacknowledged messages_uncommitted messages acks_uncommitted consumers transactions memory),vhost).map { |h|
      to_integers(h, "transactions","messages","messages_unacknowledged","messages_uncommitted","acks_uncommitted","messages_ready","consumers")
      to_booleans(h,"auto_delete","durable")
    }
  end

  

  def exchanges(vhost=nil)
    query("list_exchanges",%w(name type durable auto_delete arguments),vhost)
  end

  def connections
    query("list_connections",%w(node address port peer_address peer_port state channels user vhost timeout frame_max recv_oct recv_cnt send_oct send_cnt send_pend))
  end

  def restart
    `rabbitmqctl stop_app`
    `rabbitmqctl reset`
    `rabbitmqctl start_app`
    true
  end

  private
  
  def to_integers(hash,*names)
    names.each do |name|
      hash[name] = Integer(hash[name])
    end
    hash
  end

  def to_booleans(hash,*names)
    names.each do |name|
      hash[name] = case hash[name]
                   when "false"
                     false
                   when "true"
                     true
                   end
    end
    hash
  end
  
  def query(cmd,fields,vhost=nil)
    vhost = vhost ? "-p #{vhost}" : ""
    `rabbitmqctl #{vhost} #{cmd} #{fields.join " "}`.split("\n")[1..-2].map { |l|
      items = l.split("\t")
      h = {}
      fields.each_with_index do |key,i|
        h[key] = items[i]
      end
      h
    }
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
      Thread.new { EM.run }
    end
  end

  attr_reader :settings, :mq
  def initialize(settings={})
    self.class.ensure_eventmachine
    @settings = self.class.default_settings.merge(settings)
    @mq = MQ.new(AMQP.connect(@settings))
  end

  def publish(name,message,opts={})
    @mq.publish(name,message,opts)
  end
end

class Donkey::Message
  require 'bert'

  class Call < self
  end

  class Cast < self
  end

  TAG_TO_CLASS = {
    "call" => Call
  }
  CLASS_TO_TAG = TAG_TO_CLASS.inject({}) do |h,(k,v)|
    h[v] = k
    h
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

  # def self.decode
    
#   end

  attr_reader :to, :meta, :data
  def initialize(to_name,data,meta={})
    @to   = to_name
    @data = data
    @meta = meta
  end

  def tagged_data
    [tag,@data]
  end
  
  def payload
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
      @queue.pop(opts) do |header,payload|
        
      end
    end

    def call(to,data,meta={})
      publish(Donkey::Message::Call.new(to,data,meta))
    end

    def cast(to,data,meta={})
      publish(Donkey::Message::Cast.new(to,data,meta))
    end

    private
    
    def publish(message)
      channel.publish(message.to,message.payload,message.meta.merge(:key => ""))
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
