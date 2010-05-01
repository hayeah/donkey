require 'rubygems'
require 'rake'

require 'net/http'
require 'fileutils'
require 'open-uri'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "donkey"
    gem.summary = %Q{AMQP actor}
    gem.description = %Q{stealing from erlang}
    gem.email = "hayeah@gmail.com"
    gem.homepage = "http://github.com/hayeah/donkey"
    gem.authors = ["Howard Yeh"]
    gem.add_dependency "bert"
    gem.add_dependency "amqp"
    gem.add_development_dependency "rspec"
    gem.add_development_dependency "rr"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "donkey #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

namespace :rabbit do
  desc "donload rabbitmq tar.gz"
  # download into project root
  task :download do
    unless File.exists?('/tmp/rabbitmq-server-1.7.2.tar.gz')
      url = "http://www.rabbitmq.com/releases/rabbitmq-server/v1.7.2/rabbitmq-server-1.7.2.tar.gz"
      open('rabbitmq-server-1.7.2.tar.gz', 'wb') do |file|
        file.write(open(url).read)
      end
    end

    unless File.directory?('rabbitmq-server-1.7.2')
      sh('tar xzf rabbitmq-server-1.7.2.tar.gz')
    end
  end

  desc "make rabbitmq"
  task :make => [:download] do
    sh("cd rabbitmq-server-1.7.2 && make all && cd ..")
  end

  desc "run rabbitmq in a dtach session (requires erlang)"
  task :run => [:make] do
    socket = File.expand_path("rabbitmq.dtach")
    puts 'Detach with Ctrl+\  Re-attach with rake redis:attach'
    sleep(3)
    Dir.chdir("rabbitmq-server-1.7.2")
    #run_rabbit = "LOG_BASE=#{log_dir} MNESIA_BASE=#{mnesia_dir} dtach -A #{socket} -c make run"
    run_rabbit = "dtach -A #{socket} make run"
    puts run_rabbit
    exec(run_rabbit)
  end

  desc "attach to a running rabbitmq dtach session"
  task :attach do
    puts "Rabbitmq is not running. Try `rake rabbit:run'" unless File.exist?("rabbitmq.dtach")
    sh("dtach -a rabbitmq.dtach")
  end
end


# stolen from redis-rb
namespace :dtach do
  
  desc 'About dtach'
  task :about do
    puts "\nSee http://dtach.sourceforge.net/ for information about dtach.\n\n"
  end
  
  desc 'Install dtach 0.8 from source'
  task :install => [:about] do
    
    Dir.chdir('/tmp/')
    unless File.exists?('/tmp/dtach-0.8.tar.gz')
      url = 'http://downloads.sourceforge.net/project/dtach/dtach/0.8/dtach-0.8.tar.gz'
      open('/tmp/dtach-0.8.tar.gz', 'wb') do |file| file.write(open(url).read) end
    end

    unless File.directory?('/tmp/dtach-0.8')    
      system('tar xzf dtach-0.8.tar.gz')
    end
    
    Dir.chdir('/tmp/dtach-0.8/')
    sh 'cd /tmp/dtach-0.8/ && ./configure && make'    
    sh 'sudo cp /tmp/dtach-0.8/dtach /usr/bin/'
    
    puts 'Dtach successfully installed to /usr/bin.'
  end
end
  
