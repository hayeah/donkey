require 'rubygems'
require '../lib/ass.rb'

ASS.start(:host => 'localhost',
          #:vhost => "/ass-test",
          :logging => false) do
  s = ASS.new("foo")
  c = s.client.react {
    def foo(data)
      p [:c,Process.pid,data]
    end
  }
  
  c_keyed = s.client(:key => "unique-#{Process.pid}").
    queue(:auto_delete => true).react {
    def foo(data)
      #p [:header,header]
      p [:u,Process.pid,data]
    end
  }

  i = 0
  EM.add_periodic_timer(1) {
    data = [Process.pid,i]
    i += 1
    c.call :foo, data
    c.call :foo_cast, [:cast,data]
    c_keyed.call :foo, data
  }
  
end
