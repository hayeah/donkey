require 'thread'
class ASS::Server
  attr_reader :name
  attr_reader :thread
  
  def initialize(name,opts={})
    @name = name
    # the server is a fanout (ignores routing key)
    @exchange = ASS.mq.fanout(name,opts)
  end

  def exchange
    @exchange
  end

  def queue(opts={})
    unless @queue
      @queue ||= ASS.mq.queue(self.name,opts)
      @queue.bind(self.exchange)
    end
    self
  end

  # where the actor should ack each message it processes
  def ack?
    @ack == true
  end

  # takes options available to MQ::Queue# takes options available to MQ::Queue#subscribe
  def react(callback=nil,opts=nil,&block)
    if block
      opts = callback
      callback = block
    end
    opts = {} if opts.nil?
    
    # second call would just swap out the callback.
    @factory = ASS::Callback.factory(callback)
    
    return(self) if @subscribed
    @subscribed = true
    @ack = opts[:ack]
    self.queue unless @queue

    @events = Queue.new
    @thread = Thread.new do
      loop do
        header, content = @events.pop
        @factory.process!(self,header,content)
      end
    end
    # TODO implement on_exit semantic
    @thread.abort_on_exception = true

    @queue.subscribe(opts) do |header,content|
      @events << [header, ASS.serializer.load(content)]
    end
    
    self
  end

  # unsuscribe from the queue
  def stop(&block) # allows callback
    if block
      @queue.unsubscribe(&block)
    else
      @queue.unsubscribe
    end
    @subscribed = false
  end

  def call(name,method,data,opts={},meta=nil)
    reply_to = opts[:reply_to] || self.name
    ASS.call(name,
             method,
             data,
             opts.merge(:reply_to => reply_to),
             meta)
    
  end

  def cast(name,method,data,opts={},meta=nil)
    reply_to = nil # the remote server will not reply
    ASS.call(name,
             method,
             data,
             opts.merge(:reply_to => nil),
             meta)
  end

  def inspect
    "#<#{self.class} #{self.name}>"
  end
end
