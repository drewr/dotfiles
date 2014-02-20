# == Class: sudo::package
#
# Installs the sudo package on various platforms.
#
# === Parameters
#
# Document parameters here.
#
# [*package*]
#   The name of the sudo package to be installed
#
# [*package_ensure*]
#   Ensure if present or absent
#
# [*package_source*]
#   Where to find the sudo packge, should be a local file or a uri
#
# === Examples
#
#  class { sysdoc::package
#    package => 'sudo',
#  }
#
# === Authors
#
# Toni Schmidbauer <toni@stderr.at>
#
# === Copyright
#
# Copyright 2013 Toni Schmidbauer
#
class sudo::package(
  $package,
  $package_ensure = 'present',
  $package_source = '',
  ) {

    case $::osfamily {
      aix: {
        class { 'sudo::package::aix':
          package => $package,
          package_source => $package_source,
          package_ensure => $package_ensure,
        }
      }
      default: {
        package { $package:
          ensure => $package_ensure,
        }
      }
    }
}
