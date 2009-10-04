#   class Topic
#     def initialize(name,opts={})
#       @exchange = MQ.topic(name,opts)
#     end

#     def publish(key,payload,opts={})
#       @exchange.publish(::Marshal.dump(payload),opts.merge(:routing_key => key))
#     end

#     def subscribe(matcher,opts={},&block)
#       ack = opts.delete(:ack)
#       uid = "#{@exchange.name}.topic.#{rand 999_999_999_999}"
#       q = MQ.queue(uid,opts)
#       q.bind(@exchange.name,:key => matcher)
#       q.subscribe(:ack => ack) { |info,payload|
#         payload = ::Marshal.load(payload)
#         if block.arity == 2
#           block.call(info,payload)
#         else
#           block.call(payload)
#         end
#       }
#       q
#     end
#   end
