require 'rubygems'
require 'lib/ass.rb'

key = ARGV[0]

ASS.start(:logging => false) do
  ASS.server("foo",:key => key) {
    define_method(:on_cast) do |i|
      p [:on_cast,key,i]
      i + 1
    end
  }
end
