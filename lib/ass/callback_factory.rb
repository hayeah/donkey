class ASS::CallbackFactory

  module ServiceMethods
    def resend
      throw(:__ass_resend)
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
  
  def initialize(callback)
    @factory = build_factory(callback)
  end

  def callback_for(server,header,payload)
    # method,data
    if @factory.is_a? Class
      if @factory.respond_to? :version
        klass = @factory.get_version(payload[:version])
      else
        klass = @factory
      end
      obj = klass.new
    else
      obj = @factory
    end
    obj.instance_variable_set("@__service__",server)
    obj.instance_variable_set("@__header__",header)
    obj.instance_variable_set("@__method__",payload[:method])
    obj.instance_variable_set("@__data__",payload[:data])
    obj.instance_variable_set("@__meta__",payload[:meta])
    obj.instance_variable_set("@__version__",payload[:version])
    obj
  end

  private

  def build_factory(callback)
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
  

  
end
