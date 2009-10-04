# TODO should prolly have the option of using
# non auto-delete queues. This would be useful
# for logger. Maybe if a peeper name is given,
# then create queues with options.
class Peeper
  include Callback
  attr_reader :server_name
  def initialize(server_name,callback)
    @server_name = server_name
    @clients = {}
    @callback = build_callback(callback)
    
    uid = "#{@server_name}.peeper.#{rand 999_999_999_999}"
    q = MQ.queue uid, :auto_delete => true
    q.bind(@server_name) # messages to the server would be duplicated here.
    q.subscribe { |info,payload|
      payload = ::Marshal.load(payload)
      # sets context, but doesn't make the call
      obj = prepare_callback(@callback,info,payload)
      # there is a specific method we want to call.
      obj.server(payload[:method],payload[:data])

      # bind to peep client message queue if we've not seen it before.
      unless @clients.has_key? info.routing_key
        @clients[info.routing_key] = true
        client_q = MQ.queue "#{uid}--#{info.routing_key}",
        :auto_delete => true
        # messages to the client would be duplicated here.
        client_q.bind("#{server_name}--", :routing_key => info.routing_key) 
        client_q.subscribe { |info,payload|
          payload = ::Marshal.load(payload)
          obj = prepare_callback(@callback,info,payload)
          obj.client(payload[:method],payload[:data])
        }
      end
    }
  end
end
