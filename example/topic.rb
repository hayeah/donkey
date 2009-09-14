require 'rubygems'
require 'lib/ass.rb'


ASS.start {
  t = ASS.topic("test-topic",:auto_delete => true)
  t.subscribe("#", :auto_delete => true) { |payload|
    p [:all,payload]
  }
  t.subscribe("foo.*",:auto_delete => true) { |payload|
    p [:foo,payload]
  }
  t.subscribe("bar.*",:auto_delete => true) { |payload|
    p [:bar,payload]
  }
  i = 0
  EM.add_periodic_timer(1) {
    puts
    t.publish("foo.1","foo1-#{i}")
    t.publish("foo.2","foo2-#{i}")
    t.publish("bar.1","bar1-#{i}")
    t.publish("bar.2","bar2-#{i}")
    t.publish("blah","blah-#{i}")
    i += 1
  }
}
