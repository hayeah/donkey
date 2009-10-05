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
  def react(_callback=nil,_opts=nil,&_block)
    if _block
      _opts = _callback
      _callback = _block
    end
    _opts = {} if _opts.nil?
    
    # second call would just swap out the callback.
    @factory = ASS::CallbackFactory.new(_callback)
    
    return(self) if @subscribed
    @subscribed = true
    @ack = _opts[:ack]
    self.queue unless @queue

    # yikes!! potential for scary bugs
    @queue.subscribe(_opts) do |info,payload|
      payload = ::Marshal.load(payload)
      #p [info,payload]
      callback_object = @factory.callback_for(self,info,payload)
      proc { #|callback_object=prepare_callback(@callback,info,payload)|
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
          when :resend
            # resend the same message
            ASS.call(self.name,
                     payload[:method],
                     payload[:data], {
                       :reply_to => info.reply_to, # this could be nil for cast
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
      }.call

      
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

  def with_handlers
    not_discarded = false
    not_resent = false
    not_raised = false
    result = nil
    error = nil
    catch(:__ass_discard) do
      catch(:__ass_resend) do
        begin
          result = yield
          not_raised = true
        rescue => e
          error = e
        end
        not_resent = true
      end
      not_discarded = true
    end

    if not_discarded && not_resent && not_raised
      [:ok,result]
    elsif not_discarded == false
      [:discard]
    elsif not_resent == false
      [:resend] # resend original payload
    elsif not_raised == false
      [:error,error]
    end
  end
end
