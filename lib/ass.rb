$:.unshift File.expand_path(File.dirname(File.expand_path(__FILE__)))
require 'mq'

module ASS; end
require 'ass/amqp' # monkey patch stolen from nanite.
require 'ass/server' # monkey patch stolen from nanite.
require 'ass/callback_factory'
require 'ass/actor'
require 'ass/rpc'
require 'ass/client'
# TODO a way to specify serializer (json, marshal...)
module ASS

  class << self
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

    #MQ = nil
    def start(settings={})
      raise "should have one ASS per eventmachine" if EM.reactor_running? == true # allow ASS to restart if EM is not running.
      EM.run {
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

    def cast(name,method,data,opts,meta)
      call(name,method,data,opts.merge(:reply_to => nil),meta)
    end
    
    def call(name,method,data,opts,meta)
      payload = {
        #:type => type,
        :method => method,
        :data => data,
        :meta => meta,
      }
      payload.merge(:version => opts[:version]) if opts.has_key?(:version)
      payload.merge(:meta => opts[:meta]) if opts.has_key?(:meta)
      # this would create a dummy MQ exchange
      # object for the sole purpose of publishing
      # the message. Will not clobber existing
      # server already started in the process.
      @mq.direct(name,:no_declare => true).publish(::Marshal.dump(payload),opts)
      true
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
