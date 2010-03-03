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

  def inspect
    "#<#{self.class}:#{object_id}>"
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

    def back(reply_to,data,tag,opts={})
      reply_to.match(/^(.+)#(.+)$/)
      donkey_name = $1
      donkey_id = $2
      publish(donkey_name,
              Donkey::Message::Back.new(data),
              opts.merge({ :message_id => tag.to_s,
                           :routing_key => donkey_id}))
    end
  end

  class Topic < self
    def self.topic(name,opts={})
      channel.topic(name,opts)
    end
    
    def declare
      @queue = channel.queue(queue_name)
    end

    def listen(exchange_name,key)
      queue.bind(exchange_name,:routing_key => key)
    end

    def unlisten(exchange_name,key)
      queue.unbind(exchange_name,:routing_key => key)
    end

    def event(name,key,data,opts={})
      publish(name,
              Donkey::Message::Event.new(data),
              opts.merge({ :routing_key => key}))
    end

    private
    
    def queue_name
      "#{donkey.name}.topic"
    end
  end

  class Fanout < self
    def declare
      @exchange = channel.fanout("#{donkey.name}.fanout")
      @queue = channel.queue("#{donkey.id}.fanout",:auto_delete => true).bind("#{donkey.name}.fanout")
    end

    def bcast(to,data,opts={})
      publish("#{to}.fanout",
              Donkey::Message::BCast.new(data),
              opts)
    end

    def bcall(to,data,tag,opts={})
      publish("#{to}.fanout",
              Donkey::Message::BCall.new(data),
              opts.merge(:reply_to => "#{@donkey.name}##{@donkey.id}",
                         :message_id => tag.to_s))
    end

    def bback(reply_to,data,tag,opts={})
      reply_to.match(/^(.+)#(.+)$/)
      donkey_name = $1
      donkey_id = $2
      publish(donkey_name,
              Donkey::Message::BBack.new(data),
              opts.merge({ :message_id => tag.to_s,
                           :routing_key => donkey_id}))
    end
  end
end
