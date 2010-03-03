

class Donkey::Message
  require 'bert'

  class DecodeError < Donkey::Error
  end

  class Call < self
  end

  class Back < self
  end
  
  class Cast < self
  end

  class Event < self
  end

  TAG_TO_CLASS = {
    "call" => Call,
    "cast" => Cast,
    "back" => Back,
    "event" => Event
  }
  CLASS_TO_TAG = TAG_TO_CLASS.inject({}) do |h,(k,v)|
    h[v] = k
    h
  end

  def self.decode(payload)
    begin
      tag, data = BERT.decode(payload)
      tag_to_class(tag).new(data)
    rescue
      raise DecodeError, payload
    end
  end

  def self.tag_to_class(tag)
    TAG_TO_CLASS[tag] || raise("no class for tag: #{tag}")
  end

  def self.class_to_tag(klass)
    CLASS_TO_TAG[klass] || raise("no tag for class: #{self}")
  end

  def self.tag
    @tag ||= class_to_tag(self)
    @tag
  end

  def tag
    self.class.tag
  end

  attr_reader :data
  def initialize(data)
    @data = data
  end

  def tagged_data
    [tag,@data]
  end
  
  def encode
    BERT.encode(self.tagged_data)
  end
end
