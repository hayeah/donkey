require 'timer'

th = Thread.new { EM.run }
th.abort_on_exception = true

s = Timer.server("timer-test")

t = Timer.client("timer-test")

foo = ASS.new("foo")
foo_c = foo.client.react {
  def foo(data)
    p [:foo_c,data]
    #EM.stop_event_loop
  end
}

(1..2).each { |i|
  timer = t.call_after(foo_c,i*5,:foo,[:timer,i]).wait
  p [:timer_ticket,timer]
}

th.join

# f = c.after(5,"mememe","tomorrow","args")
# p [:ticket,f.wait(3) { "dead" }]
