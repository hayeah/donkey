class MQ
  # This method publishes a staged file message to a specific exchange.
  # The file message will be routed to queues as defined by the exchange
  # configuration and distributed to any active consumers when the
  # transaction, if any, is committed.
  #
  #  exchange = MQ.direct('name', :key => 'foo.bar')
  #  exchange.publish("some data")
  #
  # The method takes several hash key options which modify the behavior or 
  # lifecycle of the message.
  #
  # * :routing_key => 'string'
  #
  # Specifies the routing key for the message.  The routing key is
  # used for routing messages depending on the exchange configuration.
  #
  # * :mandatory => true | false (default false)
  #
  # This flag tells the server how to react if the message cannot be
  # routed to a queue.  If this flag is set, the server will return an
  # unroutable message with a Return method.  If this flag is zero, the
  # server silently drops the message.
  #
  # * :immediate => true | false (default false)
  #
  # This flag tells the server how to react if the message cannot be
  # routed to a queue consumer immediately.  If this flag is set, the
  # server will return an undeliverable message with a Return method.
  # If this flag is zero, the server will queue the message, but with
  # no guarantee that it will ever be consumed.
  #
  #  * :persistent
  # True or False. When true, this message will remain in the queue until 
  # it is consumed (if the queue is durable). When false, the message is
  # lost if the server restarts and the queue is recreated.
  #
  # For high-performance and low-latency, set :persistent => false so the
  # message stays in memory and is never persisted to non-volatile (slow)
  # storage.
  #
  def publish name, data, opts = {}
    self.callback{
      out = []

      out << Protocol::Basic::Publish.new({ :exchange => name,
                                            :routing_key => opts.delete(:key) }.merge(opts))

      data = data.to_s

      out << Protocol::Header.new(Protocol::Basic,
                                  data.length, { :content_type => 'application/octet-stream',
                                    :delivery_mode => (opts.delete(:persistent) ? 2 : 1),
                                    :priority => 0 }.merge(opts))

      out << Frame::Body.new(data)

      self.send *out
    }
    self
  end
end
