include wget

class stream2es() {
  $stream2es = "/usr/local/bin/stream2es"

  package {"daemontools": ensure => "present" }

  package {"openjdk-7-jdk": ensure => "present" }
  
  wget::fetch { "stream2es":
    source      => "http://download.elasticsearch.org/stream2es/stream2es",
    destination => $stream2es,
    timeout     => 0,
    verbose     => false,
  }
               
  file { $stream2es:
    mode => 755,
    owner   => "root",
    group   => "root",
    require => Exec["wget-stream2es"],
  }

  file { ["/etc/svc",
          "/etc/svc/stream2es",
          "/etc/svc/stream2es/log"]:
    ensure  => directory,
    owner   => "root",
    group   => "root",
    mode    => 0755,
  }

  file { "/etc/svc/stream2es/log/main":
    ensure  => directory,
    owner   => "nobody",
    group   => "nogroup",
    mode    => 0755,
  }

}
