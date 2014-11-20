use 5.006;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

name     'Mail-Milter-Authentication';
all_from 'lib/Mail/Milter/Authentication.pm';
author   q{Marc Bradshaw <marc@marcbradshaw.net>};
license  'artistic2';

perl_version 5.006;

tests_recursive('t');

resources (
   #homepage   => 'http://yourwebsitehere.com',
   #IRC        => 'irc://irc.perl.org/#Mail-Milter-Authentication',
   license    => 'http://www.perlfoundation.org/artistic_license_2_0',
   repository => 'https://gitlab.com/marcbradshaw/authentication-milter/',
   bugtracker => 'https://gitlab.com/marcbradshaw/authentication-milter/issues/',
);

configure_requires (
   'Module::Install' => 0,
);

build_requires (
   'Test::More' => 0,
);

requires (
    'Email::Address',
    'JSON',
    'Mail::DKIM::Verifier',
    'Mail::DMARC::PurePerl',
    'Mail::SPF',
    'Net::DNS',
    'Net::IP',
    'Proc::Daemon',
    'Sendmail::PMilter',
    'Socket',
    'Sys::Syslog', 
);

install_script (
    'bin/authentication_milter',
);

install_share (
    'share',
);

install_as_cpan;
auto_install;
WriteAll;