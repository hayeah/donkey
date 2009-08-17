require 'rubygems'
require '../lib/ass.rb'

AMQP.start(:host => 'localhost',
           #:vhost => "/ass-test",
           :logging => false) do
  s = ASS.peep("foo") {
    def client(method,data)
      p [:peep,:client,header.routing_key,
         method,
         data]
    end

    def server(method,data)
      p [:peep,:server,header.routing_key,
         method,
         data]
    end
  }
end
