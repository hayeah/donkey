class Donkey::WaiterMap
  require 'set'

  class RepeatedCheckin < Donkey::Error
  end

  attr_reader :map
  def initialize
    @map = Hash.new { |h,k| h[k] = Set.new }
  end

  def register(waiter,*keys)
    keys.each do |key|
      @map[key] << waiter
    end
  end

  # waiter is responsible of unregistering itself
  def unregister(waiter,*keys)
    keys.each do |key|
      waiters = @map[key].delete(waiter)
      @map.delete(key) if waiters.empty?
    end
  end

  def signal(key,value)
    waiters_of(key).each { |waiter| waiter.signal(key,value) }
  end

  def waiters_of(key)
    @map[key]
  end
end
