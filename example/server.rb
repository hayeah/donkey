require 'rubygems'
require '../lib/ass.rb'

AMQP.start(:host => 'localhost',
           #:vhost => "/ass-test",
           :logging => false) do
  s = ASS.new("foo").react {
    def foo(data)
      p [:server,data]
      data
    end
    
  }
  
end
