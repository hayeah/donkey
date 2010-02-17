module Donkey::Rabbit
  extend self

  def vhosts
    `rabbitmqctl list_vhosts`.split("\n")[1..-2]
  end

  def bindings(vhost=nil)
    query("list_bindings",%w(exchange_name queue_name routing_key arguments),vhost)
  end
  
  def queues(vhost=nil)
    query("list_queues",%w(name durable auto_delete arguments messages_ready messages_unacknowledged messages_uncommitted messages acks_uncommitted consumers transactions memory),vhost).map { |h|
      to_integers(h, "transactions","messages","messages_unacknowledged","messages_uncommitted","acks_uncommitted","messages_ready","consumers")
      to_booleans(h,"auto_delete","durable")
    }
  end

  

  def exchanges(vhost=nil)
    query("list_exchanges",%w(name type durable auto_delete arguments),vhost)
  end

  def connections
    query("list_connections",%w(node address port peer_address peer_port state channels user vhost timeout frame_max recv_oct recv_cnt send_oct send_cnt send_pend))
  end

  def restart
    `rabbitmqctl stop_app`
    `rabbitmqctl reset`
    `rabbitmqctl start_app`
    true
  end

  private
  
  def to_integers(hash,*names)
    names.each do |name|
      hash[name] = Integer(hash[name])
    end
    hash
  end

  def to_booleans(hash,*names)
    names.each do |name|
      hash[name] = case hash[name]
                   when "false"
                     false
                   when "true"
                     true
                   end
    end
    hash
  end
  
  def query(cmd,fields,vhost=nil)
    vhost = vhost ? "-p #{vhost}" : ""
    `rabbitmqctl #{vhost} #{cmd} #{fields.join " "}`.split("\n")[1..-2].map { |l|
      items = l.split("\t")
      h = {}
      fields.each_with_index do |key,i|
        h[key] = items[i]
      end
      h
    }
  end
end
