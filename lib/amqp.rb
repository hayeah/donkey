
# monkey patch to the amqp gem that adds :no_declare => true option for new 
# Exchange objects. This allows us to send messeages to exchanges that are
# declared by the mappers and that we have no configuration priviledges on.
# temporary until we get this into amqp proper
MQ::Exchange.class_eval do
  def initialize mq, type, name, opts = {}
    @mq = mq
    @type, @name, @opts = type, name, opts
    @mq.exchanges[@name = name] ||= self
    @key = opts[:key]

    @mq.callback{
      @mq.send AMQP::Protocol::Exchange::Declare.new({ :exchange => name,
                                                 :type => type,
                                                 :nowait => true }.merge(opts))
    } unless name == "amq.#{type}" or name == ''  or opts[:no_declare]
  end
end
