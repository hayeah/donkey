class ASS::Topic
  class << self
    def tunnel(name,opts={})
      MQ.topic(name,opts)
    end

    def event(name,key,data,opts={})
      ASS.dummy_exchange(name).publish(ASS.serializer.dump(data),
                                       opts.merge(:routing_key => key))
    end

    def funnel(tunnel_name,funnel_name,key_matcher,opts={},&block)
      # actor should respond to on_event(key,data)
      funnel = Funnel.new(tunnel_name,funnel_name,key_matcher,opts)
      if block
        funnel.react(&block)
      end
      funnel
    end
  end

  class Funnel
    def initialize(tunnel_name,funnel_name,key_matcher,opts={})
      @funnel_name = funnel_name
      @exchange = ASS.dummy_exchange(tunnel_name)
      @matcher = key_matcher
      self.queue(opts) if opts
      self
    end
    
    def queue(opts={})
      unless @queue
        @queue = MQ.queue(@funnel_name,opts)
        @queue.bind(@exchange.name,
                    opts.merge({ :key => @matcher }))
      end
      self
    end

    def react(callback=nil,opts={},&block)
      callback = build_callback(callback || block)
      me = self
      self.queue
      @queue.subscribe(opts) do |info,payload|
        data = ASS.serializer.load(payload)
        handler = callback.new
        work = lambda {
          begin
            handler.send(:on_event,info.routing_key,data)
          rescue => e
            me.unhandled_error(e)
          end
        }
        done = lambda { |_|
          # nothing left to do
        }
        EM.defer work, done
      end
    end

    def unhandled_error(e)
      $stderr.puts e
      $stderr.puts e.backtrace
      ASS.stop
      raise e
    end

    def build_callback(callback)
      c = case callback
          when Proc
            Class.new &callback
          when Class
            callback
          when Module
            Class.new { include callback }
          else
            raise "can build topic callback from one of Proc, Class, Module"
          end
      raise "callback must react to on_event" unless c.public_method_defined?(:on_event)
      c
    end
  end

  
  # def initialize(name,opts={})
#     @exchange = MQ.topic(name,opts)
#   end

#   def publish(key,payload,opts={})
#     @exchange.publish(::Marshal.dump(payload),opts.merge(:routing_key => key))
#   end
  
end
