$timestamp = generate("/bin/date", "+%Y-%d-%m %H:%M:%S")
$user = "drewr"

group { "puppet":
  ensure => "present",
}

File { owner => 0, group => 0, mode => 0644 }

file { '/etc/motd':
  content => "Built ${timestamp} ${ipaddress}"
}

user { $user:
  # groups => ["admin", "docker"],
  groups => ["admin"],
  password => "$6$LdYk4jGj$U1vJrG40QZEDsbWsQLvomNe2EU/Cl7wWFPfBuS3KrwAE1dbbzIcwgMYlmpKFkTDekjIZBYCKnn.o0WGQaBl/e/",
  comment => "Drew Raines",
  shell => "/usr/bin/zsh",
  managehome => "true"
}

ssh_authorized_key { $user:
  ensure => "present",
  type => "ssh-dss",
  key => "AAAAB3NzaC1kc3MAAACBAJKqbq7Ycql2sxAyA/XbuP3OOXZIpc9ttmaK7hmdVTweM+17K+FbPLE5eEeeNcmlWcCbNL1TbG8wRr5NfgxSe0lWOTyIhHp8S0jOHFAL8DFbcHD5d3YeuV8C/8Oa3Z54kcWgvQoeE6ZEuIi1HD3iX7xwSdF8X4ECKhObbk+a/M2jAAAAFQC+QBmBV8DBqtwpQt0D8awjc1ISRQAAAIAicoPYfvrSJMm1r8L9aluy7DwUbE8j4L7fyDzMqyFlHtEGSVHVuSGd4wIjej0XK+BXGbrgTpPmIR0yUSTLNUIPwAVdAuultkHTrEonxjmFV7xhZkjTJLCLFWv3/S3rcSIsTwTzI27mxR/bqlsXEjAddxmw7WCIftcFv9f8kuTjXQAAAIBXidiAyoHJIkovyvkKdZT6sXLraq6TiZu0L7ZQDHjCjrzZm4FHY/HNpEJkdPWQl/djgdWmMVgNXzr6QsrKvQzcgkM1M4zjrPrgJM/UNLD1UTbJqV3li5nkRuzkfSqndJmu4AYvRpLOzHCayaU8qlf59t3HOHK5d26cY9hdVN5zIQ==",
  user => $user
}

class { 'sudo': }
sudo::conf { $user:
  priority => 10,
  content  => "${user} ALL=(ALL) NOPASSWD: ALL",
}
sudo::conf { "admin":
  priority => 10,
  content  => "${user} ALL=(ALL) NOPASSWD: ALL",
}

package { "djbdns": ensure => "present" }
package { "htop": ensure => "present" }
package { "zsh": ensure => "present" }
package { "tmux": ensure => "present" }
package { "emacs23-nox": ensure => "present" }

$repo = "dotfiles"
class git::clone ($repo, $username=$user) {
  file { "/home/${username}/src":
    ensure  => directory,
    group   => $user,
    owner   => $username,
    mode    => 0700,
  }

  package { "git":
    ensure => installed,
  }

  vcsrepo { "/home/${username}/src/${repo}":
    ensure   => latest,
    owner    => $user,
    group    => $user,
    provider => git,
    require  => [ Package["git"] ],
    source   => "https://github.com/drewr/${repo}.git",
    revision => "master",
  }
}

class { git::clone: repo => "dotfiles" }

exec { "dotfiles":
  cwd => "/home/${user}/src/dotfiles",
  path => ["/bin", "/usr/bin", "/usr/sbin", "/usr/local/bin"],
  command => "make install",
  user => $user,
  refreshonly => true,
  # logoutput => true,
  subscribe => Vcsrepo["/home/${user}/src/dotfiles"]
}

wget::fetch { "elasticsearch":
  source      => "http://users.elasticsearch.org/drewr/elasticsearch-1.0.0.deb",
  destination => "/tmp",
  timeout     => 0,
  verbose     => false,
}

file { "/tmp/elasticsearch-1.0.0.deb":
  mode => 0755,
  owner   => "root",
  group   => "root",
  require => Exec["wget-elasticsearch"],
} ->
package { "openjdk-7-jdk":
  ensure => "present"
} ->
class { "elasticsearch":
  pkg_source => "/tmp/elasticsearch-1.0.0.deb",
  service_settings => {
    "ES_USER" => "elasticsearch",
    "ES_GROUP" => "elasticsearch",
    "ES_HEAP_SIZE" => "384m",
  },
  config     => {
    "cluster.name" => "drewr",
    "index.number_of_replicas" => "0",
    "index.number_of_shards" => "10",
    "network.bind_host" => "0.0.0.0",
    "discovery.zen.multicast.enabled" => true,
    "bootstrap.mlockall" => true,
    "logger.level" => "DEBUG",
  },
  restart_on_change => true,
}

exec { "kill the oom_killer":
  require => Service["elasticsearch"],
  command => "/bin/sleep 1; /vagrant/bin/kill-oom-killer",
}
