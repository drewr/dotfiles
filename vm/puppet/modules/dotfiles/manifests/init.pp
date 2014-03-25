class dotfiles(
  $repo="dotfiles",
  $username=$user,
  $branch="master",
) {

  $srcdir = "/home/${username}/src"

  file { $srcdir:
    ensure  => directory,
    group   => $username,
    owner   => $username,
    mode    => 0755,
  }

  package { "git":
    ensure => installed,
  }

  vcsrepo { "${srcdir}/${repo}":
    ensure   => latest,
    owner    => $username,
    group    => $username,
    provider => git,
    require  => [ Package["git"] ],
    source   => "https://github.com/${username}/${repo}.git",
    revision => $branch,
  }

  exec { "dotfiles":
    cwd => "${srcdir}/dotfiles",
    command => "env HOME=/home/${username} make install",
    user => $username,
    refreshonly => true,
    #logoutput => true,
    subscribe => Vcsrepo["${srcdir}/dotfiles"]
  }
}
