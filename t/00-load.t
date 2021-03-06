#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 21;

BEGIN {
    use_ok( 'Mail::Milter::Authentication' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Client' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Config' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Constants' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::DNSCache' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::Auth' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::AddID' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::DKIM' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::DMARC' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::LocalIP' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::PTR' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::ReturnOK' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::Sanitize' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::SenderID' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::TrustedIP' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::TLS' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::SPF' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Handler::IPRev' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Protocol::Milter' ) || print "Bail out! ";
    use_ok( 'Mail::Milter::Authentication::Protocol::SMTP' ) || print "Bail out! ";
}

diag( "Testing Mail::Milter::Authentication $Mail::Milter::Authentication::VERSION, Perl $], $^X" );

