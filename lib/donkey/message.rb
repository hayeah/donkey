class Donkey::Message
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

  class BCall < self
  end

  class BBack < self
  end

  class BCast < self
  end

  # TAG_TO_CLASS = {
  #   "call" => Call,
  #   "cast" => Cast,
  #   "back" => Back,
  #   "event" => Event,
  #   "bcall" => BCall,
  #   "bback" => BBack,
  #   "bcast" => BCast
  # }

  TAG_TO_CLASS = {
    ?0 => Call,
    ?1 => Cast,
    ?2 => Back,
    ?3 => Event,
    ?4 => BCall,
    ?5 => BBack,
    ?6 => BCast
  }
  
  CLASS_TO_TAG = TAG_TO_CLASS.inject({}) do |h,(k,v)|
    h[v] = k
    h
  end

  def self.decode(payload)
    begin
      tag = payload[0] # first byte is the tag
      data = payload[1..-1] # rest is payload
      tag_to_class(tag).new(data)
    rescue
      raise DecodeError, payload
    end
  end

  def self.tag_to_class(tag)
    TAG_TO_CLASS[tag] || raise(DecodeError.new("unrecognized tag: #{tag}")) 
  end

  def self.class_to_tag(klass)
    CLASS_TO_TAG[klass] || raise("unrecognized message class: #{klass}")
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

  # def encode
  #   data << tag
  #   data
  #   # payload = ""
  #   # payload << tag
  #   # payload << data
  #   # payload
  #    r
  # end

  def encode
    # probably more efficient if we suffix string, so ruby String can
    # take advantage of sharing.
    payload = ""
    payload << tag
    payload << data.to_s
    payload
  end
end
