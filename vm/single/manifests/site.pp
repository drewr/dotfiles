$timestamp = generate("/bin/date", "+%Y-%d-%m %H:%M:%S")

group { "puppet":
  ensure => "present",
}

File { owner => 0, group => 0, mode => 0644 }

file { '/etc/motd':
  content => "Built ${timestamp}"
}
  
user { "drewr":
  groups => ["admin"],
  password => "$6$LdYk4jGj$U1vJrG40QZEDsbWsQLvomNe2EU/Cl7wWFPfBuS3KrwAE1dbbzIcwgMYlmpKFkTDekjIZBYCKnn.o0WGQaBl/e/",
  comment => "Drew Raines",
  shell => "/bin/bash",
  managehome => "true"
}

ssh_authorized_key { "drewr":
  ensure => "present",
  type => "ssh-dss",
  key => "AAAAB3NzaC1kc3MAAACBAJKqbq7Ycql2sxAyA/XbuP3OOXZIpc9ttmaK7hmdVTweM+17K+FbPLE5eEeeNcmlWcCbNL1TbG8wRr5NfgxSe0lWOTyIhHp8S0jOHFAL8DFbcHD5d3YeuV8C/8Oa3Z54kcWgvQoeE6ZEuIi1HD3iX7xwSdF8X4ECKhObbk+a/M2jAAAAFQC+QBmBV8DBqtwpQt0D8awjc1ISRQAAAIAicoPYfvrSJMm1r8L9aluy7DwUbE8j4L7fyDzMqyFlHtEGSVHVuSGd4wIjej0XK+BXGbrgTpPmIR0yUSTLNUIPwAVdAuultkHTrEonxjmFV7xhZkjTJLCLFWv3/S3rcSIsTwTzI27mxR/bqlsXEjAddxmw7WCIftcFv9f8kuTjXQAAAIBXidiAyoHJIkovyvkKdZT6sXLraq6TiZu0L7ZQDHjCjrzZm4FHY/HNpEJkdPWQl/djgdWmMVgNXzr6QsrKvQzcgkM1M4zjrPrgJM/UNLD1UTbJqV3li5nkRuzkfSqndJmu4AYvRpLOzHCayaU8qlf59t3HOHK5d26cY9hdVN5zIQ==",
  user => "drewr"
}

package { "djbdns": ensure => "present" }
package { "htop": ensure => "present" }
package { "zsh": ensure => "present" }

class { "elasticsearch":
  java_install => true,
  version => "0.90.5",
  config     => {
    "cluster"   => {
      "name" => "foo"
    },
    "index"                => {
      "number_of_replicas" => "0",
      "number_of_shards"   => "1"
    },
    "network" => {
      "host"  => "0.0.0.0"
    }
  }
}
