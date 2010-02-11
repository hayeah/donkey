# This class was extracted from the cassandra gem by Evan Weaver
# As such, it is distributed under the terms of the apache license.
# See the APACHE-LICENSE file in the root of this project for more information.

class Time
  def self.stamp
    Time.now.stamp
  end
  
  def stamp
    to_i * 1_000_000 + usec
  end
end

# UUID format version 1, as specified in RFC 4122, with jitter in place of the mac address and sequence counter.
class Donkey::UUID
  def self.generate
    self.new.to_guid
  end

  class InvalidVersion < StandardError; end
  class TypeError < ::TypeError; end

  GREGORIAN_EPOCH_OFFSET = 0x01B2_1DD2_1381_4000 # Oct 15, 1582

  VARIANT = 0b1000_0000_0000_0000

  def initialize(bytes = nil)
    case bytes
    when self.class # UUID
      @bytes = bytes.to_s
    when String
      case bytes.size
      when 16 # Raw byte array
        @bytes = bytes
      when 36 # Human-readable UUID representation; inverse of #to_guid
        elements = bytes.split("-")
        raise TypeError, "Expected #{bytes.inspect} to cast to a #{self.class} (malformed UUID representation)" if elements.size != 5
        @bytes = elements.join.to_a.pack('H32')
      else
        raise TypeError, "Expected #{bytes.inspect} to cast to a #{self.class} (invalid bytecount)"
      end

    when Integer
      raise TypeError, "Expected #{bytes.inspect} to cast to a #{self.class} (integer out of range)" if bytes < 0 or bytes > 2**128
      @bytes = [
                (bytes >> 96) & 0xFFFF_FFFF,
                (bytes >> 64) & 0xFFFF_FFFF,
                (bytes >> 32) & 0xFFFF_FFFF,
                bytes & 0xFFFF_FFFF
               ].pack("NNNN")

    when NilClass, Time
      time = (bytes || Time).stamp * 10 + GREGORIAN_EPOCH_OFFSET
      # See http://github.com/spectra/ruby-uuid/
      @bytes = [
                time & 0xFFFF_FFFF,
                time >> 32,
                ((time >> 48) & 0x0FFF) | 0x1000,
                # Top 3 bytes reserved
                rand(2**13) | VARIANT,
                rand(2**16),
                rand(2**32)
               ].pack("NnnnnN")

    else
      raise TypeError, "Expected #{bytes.inspect} to cast to a #{self.class} (unknown source class)"
    end
  end

  def to_i
    ints = @bytes.unpack("NNNN")
    (ints[0] << 96) +
      (ints[1] << 64) +
      (ints[2] << 32) +
      ints[3]
  end

  def version
    time_high = @bytes.unpack("NnnQ")[2]
    version = (time_high & 0xF000).to_s(16)[0].chr.to_i
    version > 0 and version < 6 ? version : -1
  end

  def variant
    @bytes.unpack('QnnN')[1] >> 13
  end

  def to_guid
    elements = @bytes.unpack("NnnCCa6")
    node = elements[-1].unpack('C*')
    elements[-1] = '%02x%02x%02x%02x%02x%02x' % node
    "%08x-%04x-%04x-%02x%02x-%s" % elements
  end

  def to_json(*args)
    to_guid.to_json(*args)
  end

  def seconds
    total_usecs / 1_000_000
  end

  def usecs
    total_usecs % 1_000_000
  end

  def <=>(other)
    total_usecs <=> other.send(:total_usecs)
  end

  def inspect(long = false)
    "<Donkey::UUID##{object_id} time: #{
        Time.at(seconds).inspect
      }, usecs: #{
        usecs
      } jitter: #{
        @bytes.unpack('QQ')[1]
      }" + (long ? ", version: #{version}, variant: #{variant}, guid: #{to_guid}>" :  ">")
  end

  def <=>(other)
    self.to_i <=> other.to_i
  end

  def hash
    @bytes.hash
  end

  def eql?(other)
    other.is_a?(Comparable) and @bytes == other.to_s
  end

  def ==(other)
    self.to_s == other.to_s
  end

  def to_s
    @bytes
  end

  def sql_literal(dataset)
    dataset.literal(to_s)
  end

  private

  def total_usecs
    elements = @bytes.unpack("NnnQ")
    (elements[0] + (elements[1] << 32) + ((elements[2] & 0x0FFF) << 48) - GREGORIAN_EPOCH_OFFSET) / 10
  end
end


