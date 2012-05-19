Gem::Specification.new do |s|
  s.name        = 'activerecord_constraints'
  s.version     = '0.1.1'
  s.summary     = "Nice constraint helpers for Rails and PostgreSQL"
  s.description = "This plugin currently implements constraints for PostgreSQL only.  It
should provide a structure for a more abstract implementation.

Currently it implements foreign key constraints, unique
constraints and check constraints.  null and not null constraints
would be easy to add but they may collide with preexisting Active
Record code."
  s.authors     = ["Perry Smith"]
  s.email       = 'pedzsan@gmail.con'
  s.files       = (Dir['**/*.rb'] +
                   Dir['**/*.rake'] +
                   Dir['**/*.yml'] +
                   [ 'Rakefile', 'README', 'GNU-LICENSE' ] ).sort.uniq
  s.homepage    = 'https://github.com/pedz/activerecord_constraints'
end
