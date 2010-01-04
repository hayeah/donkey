require 'thread'
class ASS::Server
  # name and key should uniquely identify a server instance
  attr_reader :name, :key

  attr_reader :thread
  
  def initialize(name,opts={})
    @name = name.to_s
    @key = opts[:key] || ASS.random_id
    
    # create two exchanges using the same options
    @direct_e = ASS.mq.direct(name,opts)
    @cast_e   = ASS.mq.fanout("#{name}.cast",opts)
  end

  def declare_queue(opts={})
    unless @queue_declared
      @queue_declared = true
      # shared queue
      @shared_q = ASS.mq.queue(name,opts)
      @shared_q.bind(@direct_e,:key => nil)

      # private queue
      @private_q = ASS.mq.queue("#{name}.self",opts)
      @private_q.bind(@direct_e,:key => self.key)

#       # cast queue
#       @cast_q = ASS.mq.queue("#{name}.cast",opts)
#       @cast_q.bind(self.exchange,:key => nil)
      
    end
    self
  end

  alias :queue :declare_queue

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

    self.declare_queue

    @events = Queue.new
    @thread = Thread.new do
      loop do
        header, content = @events.pop
        @factory.process!(self,header,content)
      end
    end
    # TODO implement on_exit semantic
    @thread.abort_on_exception = true

    # subscription to all the queues
    @shared_q.subscribe(opts) do |header,content|
      @events << [header, ASS.serializer.load(content)]
    end
    
    self
  end

  # unsuscribe from the queue
  def stop(&block) # allows callback
    raise "broken"
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
