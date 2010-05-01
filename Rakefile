require 'rubygems'
require 'rake'

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
  
