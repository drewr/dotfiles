import "hosts.pp"
import "packages.pp"

File {
  owner => 0,
  group => 0,
  mode => 0644
}

Exec {
  path => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
}

$timestamp = chomp(generate("/bin/date", "+%Y-%d-%m %H:%M:%S"))
$user = "drewr"
$admin_user = "cloud"
$es_path = "/d/es"
$es_path_data = "${es_path}/data"
$number_of_shards = 1
$ganglia_data = "data-001"
$ganglia_client = "client-001"
$es_url = "http://users.elasticsearch.org/drewr/elasticsearch-1.0.1.deb"
$azure_plugin = "elasticsearch/elasticsearch-cloud-azure/2.0.0"
$es_settings = {
  "cluster.name" => $cluster,
  "index.number_of_replicas" => "0",
  "index.number_of_shards" => "1",
  "network.bind_host" => "0.0.0.0",
  "discovery.zen.multicast.enabled" => true,
  "bootstrap.mlockall" => true,
  "logger.level" => "TRACE",
  "plugins.isolation" => false,
  "discovery.type" => "azure",
  "cloud.azure.subscription_id" => "70bd6e77-4b1e-4835-8896-db77b8eef364",
  "cloud.azure.service_name" => $cluster,
  "cloud.azure.keystore" => "/etc/elasticsearch/azurekeystore.pkcs12",
  "cloud.azure.password" => "elastic!",
}

file { "/etc/motd":
  content => "Converged ${timestamp} ${ipaddress}\n"
}

group { "puppet":
  ensure => "present",
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

file { "/home/${user}/.ssh/config":
  owner   => $user,
  group   => $user,
  mode    => 0600,
  require => User[$user],
  content => "host github.com\n   stricthostkeychecking no\n",
}

class { "dotfiles":
  username => "drewr",
}

class { "sudo": }
sudo::conf { $user:
  priority => 10,
  content  => "${user} ALL=(ALL) NOPASSWD: ALL",
}
sudo::conf { $admin_user:
  priority => 10,
  content  => "${admin_user} ALL=(ALL) NOPASSWD: ALL",
}

### costin

user { "costin":
  groups => ["admin"],
  password => "$6$LdYk4jGj$U1vJrG40QZEDsbWsQLvomNe2EU/Cl7wWFPfBuS3KrwAE1dbbzIcwgMYlmpKFkTDekjIZBYCKnn.o0WGQaBl/e/",
  comment => "Costin Leau",
  shell => "/bin/bash",
  managehome => "true"
}

ssh_authorized_key { "costin":
  ensure => "present",
  type => "ssh-rsa",
  key => "AAAAB3NzaC1yc2EAAAABJQAAAQEA+QRwxkWYgHkoEqt5NbS0mgqE2rmURxljOByg/9XqPtLOe3Dr/VzPwZ+NolEsaAqPjCHpkROXQxFp8Hqlqh7VVeESwoAPq2mBK1apcTGeZImmb+tsu4KeyDyzW2V0C+ZoVBkzflHfJY/9N4Tvakhv/yrBlnctix8RewIDyWF79LlfsfJvG+pnseyZSxqTMeRkgQbiSEKnhxnkbR8EPVt4KEY6kM116EyPvM+R0bhk/kmkQiP0paaB0uwfHeJPzNKfCCnxF61pxEy3WkTCeg363iJVPeWkXB1iyhgbv+7esbj9csqGmQgvUGblKGPEtoyybpKQ5fls/SfsiU8+jnUpDQ==",
  user => "costin"
}

sudo::conf { "costin":
  priority => 10,
  content  => "costin ALL=(ALL) NOPASSWD: ALL",
}

####

file { "/etc/elasticsearch/azurekeystore.pkcs12":
  source => "puppet:///files/azurekeystore.pkcs12",
  mode => 0644,
  owner => "root",
  group => "root",
  before => Service["elasticsearch"],
}

package { "openjdk-7-jdk":
  ensure => "present"
}

user { "elasticsearch":
  ensure => "present",
}

class { "stream2es": }

elasticsearch::plugin { $azure_plugin:
  module_dir => "cloud-azure",
}

elasticsearch::plugin { "elasticsearch/marvel/latest":
  module_dir => "marvel",
}

file { "/usr/local/bin/kill-oom-killer":
  before => Exec["kill the oom_killer"],
  mode => 0755,
  owner => "root",
  group => "root",
  content => template("bin/kill-oom-killer"),
}

exec { "kill the oom_killer":
  require => Service["elasticsearch"],
  command => "/bin/sleep 2; /usr/local/bin/kill-oom-killer",
}

resources { "host":
  purge => true,
}

file { "diskstat":
  path => "/usr/local/bin/diskstat",
  mode => 0755,
  owner => root,
  content => template("bin/diskstat.pl"),
  require => Class["ganglia::gmond"],
}

node default {
  class { "ganglia::gmond":
    cluster_name       => "${cluster} data",
    cluster_owner      => "Elasticsearch, Inc.",
    cluster_url        => "${::domain}",
    host_location      => "home of ${::fqdn}",
    udp_send_channel   => [{port => 8649, host => $ganglia_data, ttl => 1}],
    udp_recv_channel   => [{port => 8649}],
    tcp_accept_channel => [{port => 8649}],
  }

  cron { "diskstat":
    command => "/usr/local/bin/diskstat sda sdb md0",
    require => File["diskstat"],
  }

  file { "$es_path":
    ensure => directory,
    owner => "root",
  } ->
  file { "$es_path_data":
    ensure => directory,
    owner => "elasticsearch",
  } ->
  class { "elasticsearch":
    package_url => $es_url,
    init_defaults => {
      "ES_HEAP_SIZE" => "8g",
    },
    config => merge($es_settings, {"path.data" => "$es_path_data",}),
    restart_on_change => true,
  }
}

node /client-.*/ {
  class { "ganglia::gmond":
    cluster_name       => "${cluster} client",
    cluster_owner      => "Elasticsearch, Inc.",
    cluster_url        => "${::domain}",
    host_location      => "home of ${::fqdn}",
    udp_send_channel   => [{port => 8649, host => $ganglia_client, ttl => 1}],
    udp_recv_channel   => [{port => 8649}],
    tcp_accept_channel => [{port => 8649}],
  }

  stream2es::service { "stream2es1":
    heap => "1g",
    workers => 4,
    settings => "{\\\"number_of_shards\\\":${number_of_shards}}",
    require => Class["stream2es"],
  }

  stream2es::service { "stream2es2":
    heap => "1g",
    workers => 4,
    settings => "{\\\"number_of_shards\\\":${number_of_shards}}",
    require => Class["stream2es"],
  }

  class { "elasticsearch":
    package_url => $es_url,
    init_defaults => {
      "ES_HEAP_SIZE" => "4g",
    },
    config => merge($es_settings, {"node.client" => "true",}),
    restart_on_change => true,
  }

  cron { "diskstat":
    command => "/usr/local/bin/diskstat sda sdb",
    require => File["diskstat"],
  }
}

node "data-001" {
  class{ "ganglia::web": }

  class{ "ganglia::gmetad":
    clusters => [{name     => "${cluster} data",
                  address  => $ganglia_data,},
                 {name     => "${cluster} client",
                  address  => $ganglia_client,},],
    gridname => "ES1",
  }

  class { "ganglia::gmond":
    cluster_name       => "${cluster} data",
    cluster_owner      => "Elasticsearch, Inc.",
    cluster_url        => "${::domain}",
    host_location      => "home of ${::fqdn}",
    udp_send_channel   => [{port => 8649, host => $ganglia_data, ttl => 1}],
    udp_recv_channel   => [{port => 8649}],
    tcp_accept_channel => [{port => 8649}],
  }

  exec { "reload-apache2":
    command => "/usr/sbin/service apache2 reload",
    refreshonly => true,
  }

  file { "/etc/apache2/sites-enabled/ganglia":
    ensure => symlink,
    target => "/etc/ganglia-webfrontend/apache.conf",
    notify => Exec["reload-apache2"],
    require => Class["ganglia::web"],
  }

  cron { "diskstat":
    command => "/usr/local/bin/diskstat sda sdb md0",
    require => File["diskstat"],
  }

  file { "$es_path":
    ensure => directory,
    owner => "root",
  } ->
  file { "$es_path_data":
    ensure => directory,
    owner => "elasticsearch",
  } ->
  class { "elasticsearch":
    package_url => $es_url,
    init_defaults => {
      "ES_HEAP_SIZE" => "8g",
    },
    config => merge($es_settings, {"path.data" => "$es_path_data",}),
    restart_on_change => true,
  }
}
