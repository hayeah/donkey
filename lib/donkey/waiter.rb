class Donkey::Waiter
  class Error < Donkey::Error
  end
  class NotReceived < Error
  end

  class AlreadySignaled < Error
  end

  class TimeoutAlreadySet < Error
  end

  class CallbackAlreadySet < Error
  end
  
  attr_reader :pending, :received
  attr_reader :success_callback
  def initialize(signal_map,*keys,&block)
    @success_callback = block
    @keys = keys
    @pending  = Set.new(@keys)
    @received = {} # map(key => value)
    @signal_map = signal_map
    @signal_map.register(self,*keys)
  end

  attr_reader :timeout_callback, :timer
  def timeout(time,&block)
    raise TimeoutAlreadySet,self if @timer
    @timer = EM::Timer.new(time) {on_timeout}
    @timeout_callback = block
    self
  end

  # blocking wait. you gotta call this within a
  # different thread than the EventMachine thread,
  # otherwise you'd be fucked.
  def wait!(time=nil)
    raise CallbackAlreadySet if success_callback
    q = Queue.new
    @success_callback = lambda { |*results|
      q.enq(results)
    }
    self.timeout(time) { q.enq(:timeout) } if time
    case results=q.pop
    when :timeout
      raise Donkey::Timeout
    when Array
      return results
    else
      raise "wtf?"
    end
  end

  def ready?
    @pending.empty?
  end

  def received?(key)
    @received.has_key?(key)
  end

  def value(key)
    if received?(key)
      @received[key]
    else
      raise NotReceived, key
    end
  end

  def values
    @keys.map { |key| value(key) }
  end

  def signal(key,value)
    # double signaling should not happen..?
    raise AlreadySignaled, key if received?(key)
    @pending.delete(key)
    @received[key] = value
    on_success if @pending.empty?
  end

  def status
    @status
  end
  
  def done?
    not @status.nil?
  end

  def success?
    status == :success
  end

  def timeout?
    status == :timeout
  end

  private

  def complete(status,&block)
    return if done?
    @status = status
    @signal_map.unregister(self,*@keys)
    timer.cancel if timer
    # NB to avoid timing issues, better to clean
    # up, then to call the success callback
    block.call
  end
  
  def status=(status)
    @status = status
  end
  
  def on_timeout
    complete(:timeout) do
      timeout_callback.call(self) if timeout_callback
    end
  end

  def on_success
    complete(:success) do
      success_callback.call(*values) if success_callback
    end
  end
end
