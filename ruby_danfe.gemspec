# -*- encoding : utf-8 -*-
Gem::Specification.new do |s|
  s.name        = 'ruby_danfe'
  s.version     = '0.10.0'
  s.summary     = "DANFE generator for Brazilian NFE."
  s.authors     = ["Eduardo Reboucas", "Neilson Carvalho"]
  s.email       = 'eduardo.reboucas@gmail.com'
  s.files       = ["ruby_danfe.gemspec", "lib/ruby_danfe.rb"]
  s.add_dependency('nokogiri')
  s.add_dependency('prawn')
  s.add_dependency('barby')
  s.add_dependency('burocracias', '>= 0.0.3')
  s.add_development_dependency("rake")
  s.add_development_dependency("rspec")
  s.homepage    = 'https://github.com/taxweb/ruby_danfe'
end
