require 'rubygems'
require 'lib/ass.rb'

s = nil
Thread.new do
  ASS.start do
    s = ASS.new("foo").react {
      def foo(data)
        #p [:foo,header]
        t = Time.now.to_i
        p [:s,data]
        if t % 2 == 0
          [:requeue,data]
          requeue
        end
        data
      end
    }
  end
end

i = 0
c = s.client.react {
  def foo(data)
    p ""
    p [:c,data]
  end
}

while true
  c.call(:foo,i)
  i += 1
  sleep(1)
end
