require 'rubygems'
require 'lib/ass.rb'


ASS.start {
  s = ASS.new("rpc-test").react {
    def foo(data)
      sleep(1)
      p [:rpc,data]
      [:rpc,data]
    end
  }

  RPC = s.rpc
  s2 = ASS.new("foo").react {
    def foo(i)
      # note that b/c service reaction is done in
      # a EM deferred thread, waiting on RPC
      # future doesn't block the entire machine.
      f = RPC.call :foo, i
      p [:server,f.wait,i]
      [f.wait,i]
    end
  }

  c = s2.client.react {
    def foo(i)
      p [:client,i]
    end
  }

  i = 0
  EM.add_periodic_timer(1) {
    i += 1
    c.call :foo, [Process.pid,i]
  }
  
  
}
