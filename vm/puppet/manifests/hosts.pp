class hosts($hosts) {
#   host { $::hostname:
#     ip => $::ipaddress_eth0,
#     host_aliases => $::fqdn,
#   }
  
  host { "localhost":
    ip => "127.0.0.1",
    host_aliases => "localhost.localdomain",
  }
  
  host { "ip6-localhost":
    ip => "::1",
    host_aliases => "ip6-loopback",
  }

  $h = inline_template("<% hosts.each do |k,v| -%><%= k %>:<%= v['ip'] %>;<% end -%>")
  $hs = split($h, ";")

  define make_hosts() {
    $t = split($title, "[:]")
    $n = $t[0]
    $ip = $t[1]
    
    host { $n:
      ip => $ip,
    }
  }

  make_hosts { $hs: }
}

