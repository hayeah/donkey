class ASS::Callback
  class Exit < RuntimeError
    attr_reader :from,:reason,:data
    def initialize(from,reason,data)
      @from = from
      @reason = reason
      @data = data
    end
  end

  class Discard < RuntimeError
    
  end
  
  class << self
    def factory(callback=nil,&block)
      callback ||= block
      case callback
      when Proc
        Class.new(self,&callback) 
      when Class
        raise "not a subclass of #{self}" unless callback.ancestors.include?(self)
        # maybe allow duck compatibility?
        callback
      when Module
        Class.new(self) { include callback }
      else
        raise "can build factory from one of Proc, Class, Module"
      end
    end

    def process!(*args)
      self.new(*args).process!
    end
  end

  attr_reader :server, :header, :content
  def initialize(server,header,content)
    @server = server
    @header = header
    @content = content
  end

  def process!
    type = content["type"]
    unless type =~ %r'^(call|back|cast|exit|ping|link|pong)$'
      raise "bad message type: #{type} "
    end
    dispatch = type.to_sym
    
    case dispatch
    when :call
      result = try {
        self.on_call(content["data"])
      } 
      ASS.back(respond_to=content["from"],
               from=server.name,
               content["method"],
               result,
               content["tag"],
               content["meta"])
    when :back
      try {
        self.on_back(content["data"])
      }
    when :cast
      try {
        self.on_cast(content["data"])
      }
    when :exit
      try {
        raise(Exit.new(content["from"],content["reason"],content["data"]))
      }
    end
    true
  end

  def on_call(data)
    raise "abstract"
  end

  def on_cast(data)
    raise "abstract"
  end

  def on_back(data)
    raise "abstract"
  end

  def on_error(e)
    # re-raise by default
    raise e
  end
  
  def discard!
    raise Discard
  end

  def ack!
    if @acked.nil? && server.ack?
      header.ack
      @acked = true
    end
  end

  def acked?
    @acked == true
  end

  # def resend
#     throw(:__ass_resend)
#   end
  

  def call(*args)
    @server.call(*args)
  end

  def cast(*args)
    @server.cast(*args)
  end

  private

  def try
    begin
      return(yield)
    rescue Discard
      # do nothing
    rescue => e
      begin
        self.on_error(e)
      rescue Discard
        # do nothing
      end
    ensure
      ack!
    end
  end
  
end
