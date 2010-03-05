class Donkey::Actor < Donkey::Reactor
  class Processor
    attr_reader :queue, :thread
    def initialize
      @queue = Queue.new
      @thread = Thread.new do
        background_process_loop
      end
    end

    def background_process_loop
      loop { queue.pop.process }
    end

    def enqueue(actor)
      queue.enq(actor)
    end
  end
  
  class << self
    def process(donkey,header,message,ack)
      processor.enqueue(self.new(donkey,header,message,ack))
    end

    def processor
      @processor ||= Processor.new
    end
  end
  
  def process
    super
    ack if ack?
  end
  
  def on_call
    reply(dispatch)
  end

  def on_cast
    dispatch
  end

  def on_bcall
    dispatch
  end

  def on_bcast
    dispatch
  end
  
  def dispatch
    method = message.data["method"]
    args = message.data["args"]
    self.send(method,*args)
  end

  # these could be in Donkey. synchronized versions:
  #  call! 
  
  # def call(*args)
#     receipt = donkey.call(*args)
#     wait(receipt)
#   end

#   def wait(time,*receipts)
#     q = Queue.new
#     donkey.wait(*receipts) { |*results|
#       q << [:results,results]
#     }.timeout {
#       q << :timeout
#     }
#     q.pop
#   end
  
end
