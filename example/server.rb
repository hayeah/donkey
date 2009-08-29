require 'rubygems'
require 'lib/ass.rb'

ASS.start(:host => 'localhost',
           #:vhost => "/ass-test",
          :logging => false) do
  s = ASS.new("foo").react {
    def foo(data)
      p [:foo,data]
      data
    end

    def foo_cast(data)
      p [:foo_cast,data]
      discard
    end
  }
  
end
