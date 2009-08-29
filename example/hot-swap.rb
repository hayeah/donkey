require 'rubygems'
require 'lib/ass.rb'

class Foo1
  def foo(data)
    self.service.react Foo2
    [:foo1,data]
  end
end

class Foo2
  def foo(data)
    self.service.react Foo1
    [:foo2,data]
  end
end

ASS.start(:host => 'localhost',
          #:vhost => "/ass-test",
          :logging => false) do
  s = ASS.new("foo").react(Foo1)
  c = s.client.react {
    def foo(data)
      p [:c,data]
    end
  }
  
  

  i = 0
  EM.add_periodic_timer(1) {
    data = [Process.pid,i]
    i += 1
    c.call :foo, data
  }
  
end
