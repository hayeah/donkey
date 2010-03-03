class Donkey::SignalMap
  require 'set'

  class RepeatedCheckin < Donkey::Error
  end

  attr_reader :map
  def initialize
    @map = Hash.new { |h,k| h[k] = Set.new }
  end

  def register(listener,*keys)
    keys.each do |key|
      @map[key] << listener
    end
  end

  # listener is responsible of unregistering itself
  def unregister(listener,*keys)
    keys.each do |key|
      listeners = @map[key].delete(listener)
      @map.delete(key) if listeners.empty?
    end
  end

  def signal(key,value)
    listeners_of(key).each { |listener| listener.signal(key,value) }
  end

  def listeners_of(key)
    @map[key]
  end
end
