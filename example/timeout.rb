require 'rubygems'
require '../lib/ass.rb'

# the RPC client and the EventMachine should run in different threads.
th = Thread.new { EM.run }

s = ASS.new("rpc-timeout-test",:auto_delete => true).react {
  def foo(i)
    if i % 2 == 0
      sleep(2)
    end
    [:echo,i]
  end
}

r = s.rpc
i = 0
loop {
  i += 1
  f = r.call :foo, i
  p [:rpc,f.wait(1) { :timeout },f.timeout?,f.done?]
}
