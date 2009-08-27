require 'rubygems'
require '../lib/ass.rb'
require '../lib/timer.rb'
require 'dm-core'

DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/test-timer.db")

th = Thread.new { EM.run }
th.abort_on_exception = true

s = ASS::Timer.server("timer-test")

t = ASS::Timer.client("timer-test")

foo_c = Ass.client("foo").react {
  def foo(data)
    p [:foo_c,data]
    #EM.stop_event_loop
  end
}

(1..3).each { |i|
  timer = t.call_after(foo_c,i*3,:foo,[:timer,i*3]).wait
  p [:timer_ticket,timer]
}

th.join

# f = c.after(5,"mememe","tomorrow","args")
# p [:ticket,f.wait(3) { "dead" }]
