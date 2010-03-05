class Donkey::Receipt < Struct.new(:donkey,:key)
  def wait(&block)
    donkey.wait([self],&block)
  end

  def wait!(time)
    donkey.wait!([self],time)
  end
end
