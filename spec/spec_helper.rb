$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rubygems'
require 'pp'
require 'donkey'
require 'spec'
require 'spec/autorun'

Spec::Runner.configure do |config|
  config.mock_with :rr
end

class Object
  def eigenclass(&block)
    k = class << self; self end
    if block
      k.instance_eval(&block)
    end
    k
  end
  
  def def(name,&block)
    eigenclass.instance_eval {
      define_method(name,&block)
    }
    self
  end
end
