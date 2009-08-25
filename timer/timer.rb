require 'rubygems'
require 'activerecord'
require 'monitor'
require 'ass'

module Timer
  def self.start(name)
    
  end

  def self.server(name,opts={})
    Server.new(name,opts)
  end

  def self.client(name)
    Client.new(name)
  end
  
end

class Timer::Server
  def initialize(name,opts={})
    db = {
      "adapter" => "sqlite3",
      "database" => "#{name}.sqlite3",
      "pool" => 20
      #pool: 5
      #timeout: 5000
    }
    ActiveRecord::Base.establish_connection db
    ActiveRecord::Base.logger = Logger.new("/dev/null")
    #ActiveRecord::Base.logger = Logger.new(STDERR)
    #ActiveRecord::Base.allow_concurrency = true
    ActiveRecord::Migrator.current_version
    ActiveRecord::Migrator.up("#{File.expand_path(File.dirname(File.expand_path(__FILE__)))}/migrations")
    ASS.new(name).react(self)
  end

  def after(data)
    epoch = Time.now.to_i
    t = data.delete "time"
    event_time = epoch + t
    data["event_time"] = event_time
    data["data"] = ::Marshal.dump(data["data"])
    data["options"] = ::Marshal.dump(data["options"])
    timer = OnceEvent.new data
    timer.save
    # check to see if rescheduling is needed.
    OnceScheduler.schedule(event_time)
    # reply with ticket
    timer.id
  end

  def periodic(interval,to,method,data,opts={})
    # reply immediately with ticket
  end

  def ack(ticket)
    
  end

  def cancel(ticket)
    
  end
end

class Timer::Client
  def initialize(name)
    @rpc = ASS.rpc(name)
  end

  # works for ASS::{Server,Client}
  ## hackish..
  # the opts are for MQ::Exchange#publish
  def call_after(client,time,method,data,opts={},rpc_opts={})
    # client.version
    self.after(client.name,time,
               {:method => method,
                 :data => data},
               {:routing_key => (client.respond_to?(:key) ? client.key : nil)}.merge(opts),
               rpc_opts
               )
  end

  # returns RPC future
  def after(to,time,data,opts,rpc_opts={})
    @rpc.call :after, {
      "to" => to,
      "time" => time,
      "options" => opts,
      "data" => data
    }, rpc_opts
  end

  def call_periodic(client,time,data,opts)
  end

  # returns RPC future
  def periodic(interval,to,method,data,opts,rpc_opts={})
    @rpc.call :periodic, {
      "interval" => interval,
      "data" => data,
      "options" => opts
    }, rpc_opts
  end

end

class Timer::Server::OnceScheduler
  DEFAULT_RETRY = 180 # 3 minutes (pretty arbitrary)
  self.extend(MonitorMixin)
  class << self
    # needs to be thread-safe
    def schedule(new_event_time=nil)
      self.synchronize do
        if @next_time.nil?
          # first starting up. do scheduling.
          if o = Timer::Server::OnceEvent.find(:first,:order => "event_time asc")
            @next_time = o.event_time
          else
            return
          end
        elsif new_event_time && (new_event_time < @next_time)
          # if the event_time we are told to schedule is more recent than the
          # currently set next_time, then we need to reschedule.
          @next_time = new_event_time
          EM.cancel_timer(@em_timer)
        else
          return # do nothing
        end
        secs_until = @next_time - Time.now.to_i
        secs_until =  secs_until < 0 ? 0 : secs_until
        mod = self
        @em_timer = EM.add_timer(secs_until) {
          begin
            mod.send :fire # private method
            @next_time = nil
            mod.schedule
          rescue
            p $!
          end
        }
      end
    end

    private
    
    def fire
      self.synchronize do
        es = Timer::Server::OnceEvent.find(:all, :conditions => ["event_time <= ?",Time.now.to_i])
        es.each { |t|
          # send out time event
          ASS.cast(t.to,::Marshal.load(t.data),::Marshal.load(t.options))
          if t.ack
            # sechdule timer for retry
            retry_time = t.retry || DEFAULT_RETRY
            t.event_time = t.event_time + retry_time
            t.save
          else
            # no ack required. just get rid of it.
            t.destroy
          end
        }
      end
    end
  end
end

# models
class Timer::Server::OnceEvent < ActiveRecord::Base
  set_table_name "once_events"
end

class Timer::Server::PeriodicEvent < ActiveRecord::Base
  set_table_name "periodic_events"
end

