require File.expand_path(File.dirname(__FILE__) + "/helpers")
class RabbitThor < Thor
  include Thor::Actions
  
  require 'pp'
  namespace :rabbit

  desc "vhosts","list virtual hosts on rabbitmq"
  def vhosts
    puts Donkey::Rabbit.vhosts
  end

  desc "status", "is rabbitmq started?"
  def status
    puts rabbitmqctl("status")
  end
  
  desc "reset", "reset rabbitmq"
  def reset
    rabbitmqctl("stop_app")
    rabbitmqctl("reset")
    rabbitmqctl("start_app")
  end

  desc "stop", "stop rabbitmq"
  def stop
    rabbitmqctl("stop")
  end
  
  private
  def rabbitmqctl(cmd)
    script("rabbitmqctl #{cmd}")
  end
  
  def script(cmd)
    unless File.directory?(DIR_NAME)
      if yes?("can't find rabbitmq-server, download? ")
        invoke :make
      else
        raise "no rabbitmq"
      end
    end
    inside(File.join(DIR_NAME,"scripts")) {
      return run(cmd)
    }
  end
end

# download and install tasks. more or less stolen from redis-rb
class RabbitThor
  # all these are done in relative to the directory where the thor
  # task is invoked.
  
  require 'net/http'
  require 'fileutils'
  require 'open-uri'
  DOWNLOAD_URL = "http://www.rabbitmq.com/releases/rabbitmq-server/v1.7.2/rabbitmq-server-1.7.2.tar.gz"
  FILE_NAME = "rabbitmq-server-1.7.2.tar.gz"
  DIR_NAME = File.basename(FILE_NAME,".tar.gz")
  DTACH_SOCKET = "rabbit.dtach"

  desc "download", "download and extract rabbit from rabbitmq.com"
  def download
    unless File.exists?(FILE_NAME)
      puts "downloading rabbitmq from #{DOWNLOAD_URL}"
      open(FILE_NAME, 'wb') do |file|
        file.write(open(DOWNLOAD_URL).read)
      end
    end

    unless File.directory?(DIR_NAME)
      sh('tar xzf #{FILE_NAME}')
    end
  end

  desc "make", "compile rabbitmq (requires erlang)"
  def make
    invoke :download
    inside(DIR_NAME) { run("make all") }
  end

  desc "start", "run rabbitmq in a dtach session"
  def start
    invoke :make
    if File.exist?(DTACH_SOCKET)
      puts "Rabbitmq is already running. Try `rake rabbit:attach'"
      return
    end
    puts 'Detach with Ctrl+\  Re-attach with thor rabbit:attach'
    run_rabbit = "dtach -A #{DTACH_SOCKET} make run"
    puts run_rabbit
    sleep(3)
    Dir.chdir(DIR_NAME)
    exec(run_rabbit)
  end

  desc "attach", "attach to a running rabbitmq dtach session"
  def attach
    unless File.exist?(DTACH_SOCKET)
      puts "Rabbitmq is not running. Try `thor rabbit:start'"
      return
    end
    run("dtach -a rabbitmq.dtach")
  end
end
