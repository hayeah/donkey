# collects the signaled values for the duration of the timeout
## used by bcall to collect bbacks from the donkey instances in a group.
class Donkey::Signaler
  attr_reader :signal_callback
  def initialize(signal_map,key,&block)
    @key = key
    @signal_callback = block
    @signal_map = signal_map
  end
  
  def signal(key,value)
    @signal_callback.call(value)
  end

  attr_reader :timeout_callback, :timer
  def timeout(time,&block)
    raise Donkey::NoBlockGiven unless signal_callback
    raise Donkey::TimeoutAlreadySet,self if @timer
    @signal_map.register(self,@key)
    @timer = EM::Timer.new(time) {on_timeout}
    @timeout_callback = block
    self
  end

  def wait!(time)
    raise Donkey::CallbackAlreadySet if signal_callback
    accumulator = Queue.new
    @signal_callback = lambda { |result|
      accumulator.enq(result)
    }
    q = Queue.new
    timeout(time) { q.enq(:timeout) }
    q.pop # timeout fired
    accumulator.size.times.map { accumulator.pop }
  end

  def on_timeout
    timeout_callback.call unless done?
    @signal_map.unregister(self,@key)
    @done = true
  end
  
  def done?
    @done == true
  end
end
