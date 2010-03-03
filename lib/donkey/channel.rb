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

  def inspect
    "#<#{self.class}:#{object_id}>"
  end
end
