PATH
  remote: vendor/ogems/activerecord-sqlserver-adapter-3.0.3
  specs:
    activerecord-sqlserver-adapter (3.0.3)
      activerecord (~> 3.0)

PATH
  remote: vendor/ogems/exception_notification-1.0.0
  specs:
    exception_notification (1.0.0)

PATH
  remote: vendor/ogems/state_machine-0.9.4
  specs:
    state_machine (0.9.4)

GEM
  remote: http://rubygems.org/
  specs:
    abstract (1.0.0)
    actionmailer (3.0.3)
      actionpack (= 3.0.3)
      mail (~> 2.2.9)
    actionpack (3.0.3)
      activemodel (= 3.0.3)
      activesupport (= 3.0.3)
      builder (~> 2.1.2)
      erubis (~> 2.6.6)
      i18n (~> 0.4)
      rack (~> 1.2.1)
      rack-mount (~> 0.6.13)
      rack-test (~> 0.5.6)
      tzinfo (~> 0.3.23)
    activemodel (3.0.3)
      activesupport (= 3.0.3)
      builder (~> 2.1.2)
      i18n (~> 0.4)
    activerecord (3.0.3)
      activemodel (= 3.0.3)
      activesupport (= 3.0.3)
      arel (~> 2.0.2)
      tzinfo (~> 0.3.23)
    activeresource (3.0.3)
      activemodel (= 3.0.3)
      activesupport (= 3.0.3)
    activesupport (3.0.3)
    arel (2.0.9)
    builder (2.1.2)
    erubis (2.6.6)
      abstract (>= 1.0.0)
    fastercsv (1.5.4)
    haml (3.0.25)
    i18n (0.5.0)
    libxml-ruby (1.1.3)
    mail (2.2.15)
      activesupport (>= 2.3.6)
      i18n (>= 0.4.0)
      mime-types (~> 1.16)
      treetop (~> 1.4.8)
    mime-types (1.16)
    mysql (2.8.1)
    pg (0.9.0)
    polyglot (0.3.1)
    rack (1.2.2)
    rack-mount (0.6.14)
      rack (>= 1.0.0)
    rack-test (0.5.7)
      rack (>= 1.0)
    rails (3.0.3)
      actionmailer (= 3.0.3)
      actionpack (= 3.0.3)
      activerecord (= 3.0.3)
      activeresource (= 3.0.3)
      activesupport (= 3.0.3)
      bundler (~> 1.0)
      railties (= 3.0.3)
    railties (3.0.3)
      actionpack (= 3.0.3)
      activesupport (= 3.0.3)
      rake (>= 0.8.7)
      thor (~> 0.14.4)
    rake (0.8.7)
    rubyzip (0.9.4)
    thor (0.14.6)
    thoughtbot-shoulda (2.11.1)
    treetop (1.4.9)
      polyglot (>= 0.3.1)
    tzinfo (0.3.26)
    will_paginate (3.0.pre2)

PLATFORMS
  ruby

DEPENDENCIES
  activerecord-sqlserver-adapter!
  exception_notification!
  fastercsv
  haml
  i18n (>= 0.5)
  libxml-ruby (= 1.1.3)
  mysql
  pg (= 0.9.0)
  rails (= 3.0.3)
  rubyzip
  state_machine!
  thoughtbot-shoulda
  will_paginate (~> 3.0.pre2)
