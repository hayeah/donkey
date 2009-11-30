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

    def payload
      @__payload__
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

    def call(name,method,data=nil,opts={},meta=nil)
      @__service__.call(name,method,data,opts,meta)
    end

    def cast(name,method,data=nil,opts={},meta=nil)
      @__service__.cast(name,method,data,opts,meta)
    end
  end
  
  def initialize(callback)
    @factory = build_factory(callback)
  end

  def callback_for(server,header,payload)
    # method,data
    if @factory.is_a? Class
      if @factory.respond_to? :version
        klass = @factory.get_version(payload["version"])
      else
        klass = @factory
      end
      obj = klass.new
    else
      obj = @factory
    end
    obj.instance_variable_set("@__service__",server)
    obj.instance_variable_set("@__header__",header)
    obj.instance_variable_set("@__payload__",payload)
    obj.instance_variable_set("@__method__",payload["method"])
    obj.instance_variable_set("@__data__",payload["data"])
    obj.instance_variable_set("@__meta__",payload["meta"])
    obj.instance_variable_set("@__version__",payload["version"])
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
        else
          raise "can build factory from one of Proc, Class, Module"
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
