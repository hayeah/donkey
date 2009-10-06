class ASS::Actor
  # this class is a thin layer over ASS::Server
  def initialize(name,opts={},&block)
    @server = ASS.server(name,opts)
    if block
      react(&block)
    end
  end

  def queue(opts={})
    @server.queue(opts)
    self
  end

  def react(callback=nil,opts=nil,&block)
    if block
      opts = callback
      callback = block
    end
    opts = {} if opts.nil?
    callback_factory = ASS::CallbackFactory.new(callback)
    server = @server # for closure capturing, needed for callback_factory
    @server.react(opts) {
      define_method(:on_call) do |_|
        raise "can't call an actor with method set to nil" if payload[:method].nil?
        callback_object = callback_factory.callback_for(server,header,payload)
        callback_object.send(payload[:method],payload[:data])
      end

      define_method(:on_error) do |e,_|
        callback_object = callback_factory.callback_for(server,header,payload)
        if callback_object.respond_to?(:on_error)
          callback_object.on_error(e,payload[:data])
        else
          raise e
        end
      end
    }
    self
  end

  def call(*args)
    @server.call(*args)
  end

  def cast(*args)
    @server.cast(*args)
  end
  
end
