include wget

class stream2es(
  $user="nobody",
  $group="nogroup",
  $heap="256m",
  $broker="http://localhost:9200",
  $exchange="queue",
  $queue="s2e.default",
  $target="http://localhost:9200/foo/t",
) {
  $stream2es = "/usr/local/bin/stream2es"
  $stream2es_svc_path = "/etc/svc/stream2es"
  $stream2es_service = "/etc/service/stream2es"

  package {"daemontools": ensure => "present" }
  package {"daemontools-run": ensure => "present" }

  service { "svscan":
    ensure => running,
    provider => "upstart",
  }

  wget::fetch { "stream2es":
    source      => "http://download.elasticsearch.org/stream2es/stream2es",
    destination => $stream2es,
    timeout     => 0,
    verbose     => false,
  }

  file { $stream2es:
    mode => 0755,
    owner   => "root",
    group   => "root",
    require => Exec["wget-stream2es"],
  }

  file { ["/etc/svc",
          "${stream2es_svc_path}",
          "${stream2es_svc_path}/log"]:
    ensure  => directory,
    owner   => "root",
    group   => "root",
    mode    => 0755,
  }

  file { "${stream2es_svc_path}/log/main":
    ensure  => directory,
    owner   => "nobody",
    group   => "nogroup",
    mode    => 0755,
  }

  file { "${stream2es_svc_path}/run":
    owner   => "root",
    group   => "root",
    mode    => 0755,
    content => template("$module_name/svc/run"),
    require => File["${stream2es_svc_path}", "${stream2es_svc_path}/log/run"],
  }

  file { "${stream2es_svc_path}/log/run":
    owner   => "root",
    group   => "root",
    mode    => 0755,
    content => template("$module_name/svc/log/run"),
    require => File["${stream2es_svc_path}/log"],
  }

  file { $stream2es_service:
    ensure => "link",
    target => "${stream2es_svc_path}",
    require => File["${stream2es_svc_path}/run",
                    "${stream2es_svc_path}/log/run"],
  }

  exec { "/usr/bin/svc -t ${stream2es_service}":
    subscribe => File["${stream2es_svc_path}/run"],
    refreshonly => true
  }
}
