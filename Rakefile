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
