require 'rubygems'
require 'lib/ass.rb'

ASS.start(:logging => false) do
  s = ASS.server("foo").react(:ack => true) {
    def on_call(i)
      p [header.reply_to,i]
      i += 1
    end

   #  def on_cast(data)
#       if data == 100
#         raise "aieeee"
#       end
#       p [:cast,data]
#     end

    def on_error(e,data)
      p [:error,e,data]
      #ASS.stop
    end
  }
  s.call("foo",0)
  #s.cast("foo",:foo,1)
  #s.cast("foo",:foo,100)
  #ASS.stop
end
