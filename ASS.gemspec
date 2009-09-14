# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{ASS}
  s.version = "0.0.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Howard Yeh"]
  s.date = %q{2009-09-10}
  s.email = %q{hayeah@gmail.com}
  s.extra_rdoc_files = [
    "LICENSE",
    "README.textile"
  ]
  s.files = [
    "ASS.gemspec",
    "LICENSE",
    "README.textile",
    "Rakefile",
    "VERSION.yml",
    "lib/ass.rb",
    "lib/ass/amqp.rb",
    "test/ass_test.rb",
    "test/test_helper.rb"
  ]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/hayeah/ass}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Asynchronous Service Stages for Distributed Services}
  s.test_files = [
    "test/ass_test.rb",
    "test/test_helper.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<amqp>, [">= 0"])
    else
      s.add_dependency(%q<amqp>, [">= 0"])
    end
  else
    s.add_dependency(%q<amqp>, [">= 0"])
  end
end
