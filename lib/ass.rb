$:.unshift File.expand_path(File.dirname(File.expand_path(__FILE__)))
require 'mq'

module ASS; end
require 'ass/amqp' # monkey patch stolen from nanite.
require 'ass/serializers'

require 'ass/server' # monkey patch stolen from nanite.
require 'ass/callback_factory'
require 'ass/actor'
require 'ass/rpc'
require 'ass/client'

require 'ass/topic'

module ASS

  class << self

    #MQ = nil
    def start(settings={})
      raise "should have one ASS per eventmachine" if EM.reactor_running? == true # allow ASS to restart if EM is not running.
      EM.run {
        @serializer = settings.delete(:format) || ::Marshal
        raise "Object Serializer must respond to :load and :dump" unless @serializer.respond_to?(:load) && @serializer.respond_to?(:dump)
        @mq = ::MQ.new(AMQP.start(settings))
        # ASS and its worker threads (EM.threadpool) should share the same MQ instance.
        yield if block_given?
      }
    end

    def stop
      AMQP.stop{ EM.stop }
      true
    end

    def mq
      @mq
    end

    def serializer
      @serializer
    end

    def server(name,opts={},&block)
      s = ASS::Server.new(name,opts)
      if block
        s.react(&block)
      end
      s
    end

    def actor(name,opts={},&block)
      s = ASS::Actor.new(name,opts)
      if block
        s.react(&block)
      end
      s
    end

    def rpc(opts={})
      ASS::RPC.new(opts)
    end

    # the opts is used to initiate an RPC
    def client(opts={})
      ASS::Client.new(opts)
    end

    def cast(name,method,data,meta=nil,opts={})
      payload = {
        "type" => "cast",
        "method" => method,
        "data" => data,
        "meta" => meta
      }
      publish(name,payload,opts)
      true
    end
    
    def call(name,from,method,data,meta=nil,opts={})
      # make sure the payload hash use string
      # keys. Serialization format might not
      # preserve type.
      message_id = rand(999_999_999).to_s
      payload = {
        "type" => "call",
        "from" => from,
        "method" => method,
        "data" => data,
        "tag" => message_id,
        "meta" => meta
      }
      publish(name,payload,opts)
      return message_id
    end

    def back(name,from,method,data,tag,meta=nil,opts={})
      payload = {
        "type" => "back",
        "from" => from,
        "method" => method,
        "data" => data,
        "tag" => tag,
        "meta" => meta
      }
      publish(name,payload,opts)
      true
    end

    private

    def publish(name,payload,opts={})
      dummy_exchange(name).publish(ASS.serializer.dump(payload),opts)
    end

    # this would create a dummy MQ exchange object
    # for the sole purpose of publishing the
    # message. Will not clobber existing server
    # already started in the process.
    def dummy_exchange(name)
      @mq.direct(name,:no_declare => true)
    end
  end
  
  
  #   def self.topic(name,opts={})
  #     ASS::Topic.new(name,opts)
  #   end

  

  
  # def self.peep(server_name,callback=nil,&block)
#     callback = block if callback.nil?
#     callback = Module.new {
#       def server(*args)
#         p [:server,args]
#       end

#       def client(*args)
#         p [:client,args]
#       end
#     }
#     ASS::Peeper.new(server_name,callback)
#   end

  # assumes server initializes it with an exclusive and auto_delete queue.
  
  
end
