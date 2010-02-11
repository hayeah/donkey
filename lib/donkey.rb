require 'mq'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

class Donkey
  require "donkey/uuid"
  class Error < RuntimeError
  end

  attr_reader :name, :rabbit
  def initialize(name)
    @name = name
    @reactors = []
    @rabbit = Donkey::Rabbit.new
  end

  def ping
    @reactors.map(&:on_ping)
  end

  def react(reactor)
    @reactors << reactor
  end
end

class Donkey::Rabbit
  def self.default_settings
    AMQP.settings
  end

  attr_reader :settings, :mq
  def initializes(settings={})
    @settings = self.class.default_settings.merge(settings)
    @mq = MQ.new(AMQP.connect(@settings))
  end
end

class Donkey::Pong
  attr_reader :name, :uuid
  def initialize(name,uuid)
    @name = name
    @uuid = uuid
  end
end

class Donkey::Reactor
  attr_reader :donkey, :uuid
  def initialize(donkey)
    @donkey = donkey
    @uuid = Donkey::UUID.generate
  end

  def name
    @donkey.name
  end
  
  def on_ping
    Donkey::Pong.new(name,uuid)
  end
end
