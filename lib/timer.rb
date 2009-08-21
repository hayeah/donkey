require 'ass'
require 'json'
module ASS::Timer
  # stolen from active support
  def self.symbolize_keys(h)
    h.inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end
  
  # fucking ridiculous. I just want to use blob.
  def self.load(data)
    self.symbolize_keys(JSON.parse(data)) 
  end

  def self.dump(data)
    data.to_json
  end
  
  def self.server(name,opts={})
    require 'timer/server'
    ASS::Timer::Server.new(name,opts)
  end

  def self.client(name)
    ASS::Timer::Client.new(name)
  end

  class Client
    def initialize(name)
      @rpc = ASS.rpc(name)
    end

    # works for ASS::{Server,Client}
    ## hackish..
    # the opts are for MQ::Exchange#publish
    def call_after(client,time,method,data,opts={},rpc_opts={})
      # client.version
      self.after(client.name,time,
                 {:method => method,
                  :data => data},
                 {:routing_key => (client.respond_to?(:key) ? client.key : nil)}.merge(opts),
                 rpc_opts
                 )
    end

    # returns RPC future
    def after(to,time,data,opts,rpc_opts={})
      @rpc.call :after, {
        "to" => to,
        "time" => time,
        "options" => opts,
        "data" => data
      }, rpc_opts
    end

    def call_periodic(client,time,data,opts)
    end

    # returns RPC future
    def periodic(interval,to,method,data,opts,rpc_opts={})
      @rpc.call :periodic, {
        "interval" => interval,
        "data" => data,
        "options" => opts
      }, rpc_opts
    end

  end
  
  #
end
