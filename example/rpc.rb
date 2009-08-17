require 'rubygems'
require '../lib/ass.rb'

# the RPC client and the EventMachine should run in different threads.
th = Thread.new { EM.run }

s = ASS.new("rpc-test").react {
  def foo(data)
    sleep(1)
    [:echo,data]
  end
}

r = s.rpc
i = 0
loop {
  i += 1
  future1 = r.call :foo, i
  future2 = r.call :foo, "<#{i}>"
  #p future
  #p r.futures
  p [:rpc,future1.wait]
  p [:rpc,future2.wait]
}
