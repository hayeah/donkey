class Donkey::Reactor
  require 'forwardable'
  extend Forwardable

  def_delegators :@donkey, :call, :cast, :bcall, :bcast, :event
  
  class NoAckNeeded < Donkey::Error
  end

  # seems like a bad idea to have ack as an argument to initialize...
  def self.process(donkey,header,message,ack=false)
    self.new(donkey,header,message,ack).process
  end
  
  attr_reader :donkey, :header, :message, :ack
  def initialize(donkey,header,message,ack=false)
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
      when Donkey::Message::Event
        on_event
      when Donkey::Message::BCall
        on_bcall
      when Donkey::Message::BBack
        donkey.signal(header.message_id,message.data)
      when Donkey::Message::BCast
        on_bcast
      else
        raise "fubared"
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
    raise Donkey::Error, "can only reply to a call or bcall" unless Donkey::Message::Call === message || Donkey::Message::BCall === message
    raise Donkey::Error, "can only reply once" if @replied
    @replied = true
    case message
    when Donkey::Message::Call
      donkey.back(header,message,result,opts)
    when Donkey::Message::BCall
      donkey.bback(header,message,result,opts)
    end
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

  def on_bcast
    on_cast
  end

  def on_bcall
    on_call
  end

  def on_event
    raise "abstract"
  end

  def on_error(error)
    raise error
  end
end
