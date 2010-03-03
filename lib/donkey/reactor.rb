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
      when Donkey::Message::Event
        on_event
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

  def on_event
    raise "abstract"
  end

  def on_error(error)
    raise error
  end
end
