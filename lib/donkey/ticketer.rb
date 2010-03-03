class Donkey::Ticketer
  # TODO synchronize?
  def initialize
    # @mutex = Mutex.new
    @counter = 0
  end
  
  def next
    @counter += 1
    @counter.to_s
  end
end
