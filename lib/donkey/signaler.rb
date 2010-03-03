class Donkey::Signaler
  class TimeoutAlreadySet < Donkey::Error
  end
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
    raise TimeoutAlreadySet,self if @timer
    @signal_map.register(self,@key)
    @timer = EM::Timer.new(time) {on_timeout}
    @timeout_callback = block
    self
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
