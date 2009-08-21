require 'dm-core'
require 'monitor'
class ASS::Timer::Server
  DEFAULT_RETRY = 180 # 3 minutes (pretty arbitrary)

  class Once
    self.extend(MonitorMixin)
    include DataMapper::Resource
    property :id, Serial
    property :to, String
    property :data, Text # binary
    property :options, Text # marshaled ruby option hash for ASS.cast
    property :ack, Boolean # requires client to ack a timed event explicitly. (or else resend)
    property :retry, Integer # if ack is true, resend event after retry seconds.
    
    property :event_time, Integer

    class << self
      # needs to be thread-safe
      def schedule(new_event_time=nil)
        self.synchronize do
          if @next_time.nil?
            # first starting up. do scheduling.
            if o = self.first(:order => [:event_time.asc])
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
          @em_timer = EM.add_timer(secs_until) {
            begin
              Once.send :fire_events # private method
              @next_time = nil
              Once.schedule
            rescue
              p $!
            end
          }
        end
      end

      private
      def fire_events
        # first is to fire all events before Time.now
        self.all(:event_time.lte => Time.now.to_i).each { |t|
          # send out time event
          ASS.cast(t.to,ASS::Timer.load(t.data),ASS::Timer.load(t.options))
          if t.ack
            # sechdule timer for retry
            retry_time = t.retry || ASS::Timer::Serial::DEFAULT_RETRY
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

  class Periodic
    include DataMapper::Resource
    property :id, Serial
    property :to, String
    property :data, Text # binary
    property :options, Text # binary
    property :ack, Boolean
    property :retry, Integer

    property :next_event_time, Integer
    property :interval, Text # marshaled interval spec

    class << self
      def schedule
        
      end
    end
  end
  # should output some error if auto_upgrade fails.
  ## in which case, human intervention.
  DataMapper.auto_upgrade! 

  class << self
    def new(*args)
      raise "Allows one instance of timer per process" if @singleton
      @singleton = super(*args)
      Once.schedule
      Periodic.schedule
      @singleton
    end
  end

  def initialize(name,opts={})
    ASS.new(name).react(self)
  end

#   def after(time,to,method,data,opts={})
#     # reply immediately with ticket
#     rand(10)
#   end

  def after(data)
    epoch = Time.now.to_i
    t = data.delete "time"
    event_time = epoch + t
    data["event_time"] = event_time
    data["data"] = ASS::Timer.dump(data["data"])
    data["options"] = ASS::Timer.dump(data["options"])
    timer = Once.new data
    timer.save
    # check to see if rescheduling is needed.
    Once.schedule(event_time)
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
