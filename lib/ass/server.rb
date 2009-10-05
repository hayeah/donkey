class ASS::Server
  attr_reader :name, :key
  def initialize(name,opts={})
    @name = name
    key = opts.delete :key
    @key = key ? key.to_s : @name
    @exchange = ASS.mq.direct(name,opts)
  end

  def exchange
    @exchange
  end

  def queue(opts={})
    unless @queue
      @queue ||= ASS.mq.queue("#{self.name}--#{self.key}",opts)
      @queue.bind(self.exchange,:routing_key => self.key)
    end
    self
  end

  # takes options available to MQ::Queue# takes options available to MQ::Queue#subscribe
  def react(callback=nil,opts=nil,&block)
    if block
      opts = callback
      callback = block
    end
    opts = {} if opts.nil?

    # second call would just swap out the callback.
    @callback = build_callback(callback)
    
    return(self) if @subscribed
    @subscribed = true
    @ack = opts[:ack]
    self.queue unless @queue

    # yikes!! potential for scary bugs
    @queue.subscribe(opts) do |info,payload|
      payload = ::Marshal.load(payload)
      callback_object = prepare_callback(@callback,info,payload)
      operation = proc {
        with_handlers do
          callback_object.send(:on_call,payload[:data])
        end
      }
      done = proc { |result|
        # the client MUST exist, otherwise it's an error.
        ## FIXME it's bad if the server dies b/c
        ## the client isn't there. It's bad that
        ## this can cause the server to fail.
        ##
        ## I am not sure what happens if message
        ## is unroutable. I think it's just
        ## silently dropped unless the mandatory
        ## option is given.
        case status = result[0]
        when :ok
          if info.reply_to
            data = result[1]
            # respond with cast (we don't want
            # to get a response to our response,
            # then respond to the response of
            # this response, and so on.)
            ASS.cast(info.reply_to,
                     payload[:method],
                     data, {
                       :routing_key => info.routing_key,
                       :message_id => info.message_id},
                     payload[:meta])
          end
          info.ack if @ack
        when :requeue
          # resend the same message
          ASS.call(self.name,
                   payload[:method],
                   payload[:data], {
                     :reply_to => info.reply_to,
                     :routing_key => info.routing_key,
                     :message_id => info.message_id},
                   payload[:meta])
          info.ack if @ack
        when :discard
          # no response back to client
          info.ack if @ack
        when :error
          # programmatic error. don't ack
          error = result[1]
          if callback_object.respond_to?(:on_error)
            begin
              callback_object.on_error(error,payload[:data])
              info.ack if @ack # successful error handling
            rescue => more_error
              $stderr.puts more_error
              $stderr.puts more_error.backtrace
              ASS.stop
            end
          else
            # unhandled error
            $stderr.puts error
            $stderr.puts error.backtrace
            ASS.stop
          end
          # don't ack.
        end
      }
      EM.defer operation, done
    end
    self
  end

  def call(name,data,opts={},meta=nil)
    reply_to = opts[:reply_to] || self.name
    key = opts[:key] || self.key
    ASS.call(name,
             method=nil,
             data,
             opts.merge(:key => key, :reply_to => reply_to),
             meta)
    
  end

  def cast(name,data,opts={},meta=nil)
    reply_to = nil # the remote server will not reply
    key = opts[:key] || self.key
    ASS.call(name,
             method=nil,
             data,
             opts.merge(:key => key, :reply_to => nil),
             meta)
  end

  def inspect
    "#<#{self.class} #{self.name}>"
  end

  private

  module ServiceMethods
    def requeue
      throw(:__ass_requeue)
    end
    
    def discard
      throw(:__ass_discard)
    end
    
    def header
      @__header__
    end

    def method
      @__method__
    end

    def data
      @__data__
    end

    def meta
      @__meta__
    end

    def version
      @__version__
    end

    def call(service,method,data=nil,opts={})
      @__service__.call(method,data,opts)
    end

    def cast(service,method,data=nil,opts={})
      @__service__.cast(method,data,opts)
    end
  end
  
  def build_callback(callback)
    c = case callback
        when Proc
          Class.new &callback
        when Class
          callback
        when Module
          Class.new { include callback }
        when Object
          callback # use singleton objcet as callback
        end
    case c
    when Class
      c.instance_eval { include ServiceMethods }
    else
      c.extend ServiceMethods
    end
    c
  end

  # called for each request
  def prepare_callback(callback,header,payload)
    # method,data
    if callback.is_a? Class
      if callback.respond_to? :version
        klass = callback.get_version(payload[:version])
      else
        klass = callback
      end
      obj = klass.new
    else
      obj = callback
    end
    obj.instance_variable_set("@__service__",self)
    obj.instance_variable_set("@__header__",header)
    obj.instance_variable_set("@__method__",payload[:method])
    obj.instance_variable_set("@__data__",payload[:data])
    obj.instance_variable_set("@__meta__",payload[:meta])
    obj.instance_variable_set("@__version__",payload[:version])
    obj
  end

  def with_handlers
    not_discarded = false
    not_requeued = false
    not_raised = false
    result = nil
    error = nil
    catch(:__ass_discard) do
      catch(:__ass_requeue) do
        begin
          result = yield
          not_raised = true
        rescue => e
          error = e
        end
        not_requeued = true
      end
      not_discarded = true
    end

    if not_discarded && not_requeued && not_raised
      [:ok,result]
    elsif not_discarded == false
      [:discard]
    elsif not_requeued == false
      [:requeue] # requeue original payload
    elsif not_raised == false
      [:error,error]
    end
  end
end
