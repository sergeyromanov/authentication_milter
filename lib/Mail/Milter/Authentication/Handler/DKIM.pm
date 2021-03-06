package Mail::Milter::Authentication::Handler::DKIM;
use strict;
use warnings;
use base 'Mail::Milter::Authentication::Handler';
use version; our $VERSION = version->declare('v0.1.1');

use Data::Dumper;
use English qw{ -no_match_vars };
use Sys::Syslog qw{:standard :macros};

use Mail::DKIM;
use Mail::DKIM::Verifier;
use Mail::DKIM::DNS;

sub default_config {
    return {
        'hide_none'         => 0,
        'check_adsp'        => 1,
        'show default_adsp' => 0,
        'adsp_hide_none'    => 0,
    };
}

sub envfrom_callback {
    my ( $self, $env_from ) = @_;
    $self->{'failmode'}     = 0;
    $self->{'headers'}      = [];
    $self->{'has_dkim'}     = 0;
    $self->{'carry'}        = q{};
    $self->destroy_object('dkim');
    return;
}

sub header_callback {
    my ( $self, $header, $value ) = @_;
    return if ( $self->{'failmode'} );
    my $EOL        = "\015\012";
    my $dkim_chunk = $header . ': ' . $value . $EOL;
    $dkim_chunk =~ s/\015?\012/$EOL/g;
    push @{$self->{'headers'}} , $dkim_chunk;

    if ( lc($header) eq 'dkim-signature' ) {
        $self->{'has_dkim'} = 1;
    }
    if ( lc($header) eq 'domainkey-signature' ) {
        $self->{'has_dkim'} = 1;
    }

    # Add Google signatures to the mix.
    # Is this wise?
    if ( $header eq 'X-Google-DKIM-Signature' ) {
        my $x_dkim_chunk = 'DKIM-Signature: ' . $value . $EOL;
        $x_dkim_chunk =~ s/\015?\012/$EOL/g;
        push @{$self->{'headers'}} , $x_dkim_chunk;
        $self->{'has_dkim'} = 1;
    }
    return;
}

sub eoh_callback {
    my ($self) = @_;
    return if ( $self->{'failmode'} );
    my $config = $self->handler_config();

    if ( $self->{'has_dkim'} == 0 ) {
        $self->dbgout( 'DKIMResult', 'No DKIM headers', LOG_INFO );
        if ( !( $config->{'hide_none'} ) ) {
            $self->add_auth_header(
                $self->format_header_entry( 'dkim', 'none' )
                . ' (no signatures found)' );
        }
        delete $self->{'headers'};
    }
    else {

        my $dkim;
        eval {
            $dkim = Mail::DKIM::Verifier->new();
            # The following requires Mail::DKIM > 0.4
            if ( $Mail::DKIM::VERSION >= 0.4 ) {
                my $resolver = $self->get_object('resolver');
                Mail::DKIM::DNS::resolver($resolver);
            }
            $self->set_object('dkim', $dkim, 1);
        };
        if ( my $error = $@ ) {
            $self->log_error( 'DKIM Setup Error ' . $error );
            $self->_check_error( $error );
            $self->{'failmode'} = 1;
            delete $self->{'headers'};
            return;
        }

        eval {
            $dkim->PRINT( join q{},
                @{ $self->{'headers'} },
                "\015\012",
            );
        };
        if ( my $error = $@ ) {
            $self->log_error( 'DKIM Headers Error ' . $error );
            $self->_check_error( $error );
            $self->{'failmode'} = 1;
        }

        delete $self->{'headers'};
    }

    $self->{'carry'} = q{};

    return;
}

sub body_callback {
    my ( $self, $body_chunk ) = @_;
    return if ( $self->{'failmode'} );
    return if ( $self->{'has_dkim'} == 0 );
    my $EOL = "\015\012";

    my $dkim_chunk;
    if ( $self->{'carry'} ne q{} ) {
        $dkim_chunk = $self->{'carry'} . $body_chunk;
        $self->{'carry'} = q{};
    }
    else {
        $dkim_chunk = $body_chunk;
    }

    if ( substr( $dkim_chunk, -1 ) eq "\015" ) {
        $self->{'carry'} = "\015";
        $dkim_chunk = substr( $dkim_chunk, 0, -1 );
    }

    $dkim_chunk =~ s/\015?\012/$EOL/g;

    my $dkim = $self->get_object('dkim');
    eval {
        $dkim->PRINT( $dkim_chunk );
    };
    if ( my $error = $@ ) {
        $self->log_error( 'DKIM Body Error ' . $error );
        $self->_check_error( $error );
        $self->{'failmode'} = 1;
    }
    return;
}

sub eom_callback {
    my ($self) = @_;

    return if ( $self->{'has_dkim'} == 0 );
    return if ( $self->{'failmode'} );

    my $config = $self->handler_config();

    my $dkim = $self->get_object('dkim');

    eval {
        $dkim->PRINT( $self->{'carry'} );
        $dkim->CLOSE();

        my $dkim_result        = $dkim->result;
        my $dkim_result_detail = $dkim->result_detail;

        $self->dbgout( 'DKIMResult', $dkim_result_detail, LOG_INFO );

        if ( !$dkim->signatures() ) {
            if ( !( $config->{'hide_none'} && $dkim_result eq 'none' ) ) {
                $self->add_auth_header(
                    $self->format_header_entry( 'dkim', $dkim_result )
                      . ' (no signatures found)' );
            }
        }
        foreach my $signature ( $dkim->signatures() ) {

            my $otype = ref $signature;
            my $type =
                $otype eq 'Mail::DKIM::DkSignature' ? 'domainkeys'
              : $otype eq 'Mail::DKIM::Signature'   ? 'dkim'
              :                                       'dkim';
            $self->dbgout( 'DKIMSignatureType', $type, LOG_DEBUG );

            $self->dbgout( 'DKIMSignatureIdentity', $signature->identity, LOG_DEBUG );
            $self->dbgout( 'DKIMSignatureResult',   $signature->result_detail, LOG_DEBUG );
            my $signature_result        = $signature->result();
            my $signature_result_detail = $signature->result_detail();

            if ( $signature_result eq 'invalid' ) {
                if ( $signature_result_detail =~ /DNS query timeout for (.*) at / ) {
                    my $timeout_domain = $1;
                    $self->log_error( "TIMEOUT DETECTED: in DKIM result: $timeout_domain" );
                    $signature_result_detail = "DNS query timeout for $timeout_domain";
                }
                if ( $signature_result_detail =~ /public key: panic:/ ) {
                    $self->log_error( "PANIC DETECTED: in DKIM result: $signature_result_detail" );
                    $self->exit_on_close();
                    $self->tempfail_on_error();
                    return;
                }
            }

            my $result_comment = q{};
            if ( $signature_result ne 'pass' and $signature_result ne 'none' ) {
                $signature_result_detail =~ /$signature_result \((.*)\)/;
                if ( $1 ) {
                    $result_comment = $1 . '; ';
                }
            }
            if (
                !(
                    $config->{'hide_none'} && $signature_result eq 'none'
                )
              )
            {

                my $key_data = q{};
                eval {
                    my $key = $signature->get_public_key();
                    $key_data = $key->size() . '-bit ' . $key->type() . ' key';
                };

                if ( $type eq 'domainkeys' ) {
                    ## DEBUGGING
                    my $header = join(
                        q{ },
                        $self->format_header_entry( $type, $signature_result ),
                        '('
                          . $self->format_header_comment(
                              $result_comment
                              . $key_data
                            )
                          . ')',
                        $self->format_header_entry( 'header.d', $signature->domain() ),
                        $self->format_header_entry( 'header.b', substr( $signature->data(), 0, 8 ) ),
                    );
                    $self->add_auth_header($header);
                }
                else {
                    my $header = join(
                        q{ },
                        $self->format_header_entry( $type, $signature_result ),
                        '('
                          . $self->format_header_comment(
                            $result_comment
                            . $key_data
                          )
                          . ')',
                        $self->format_header_entry( 'header.d', $signature->domain() ),
                        $self->format_header_entry( 'header.i', $signature->identity() ),
                        $self->format_header_entry( 'header.b', substr( $signature->data(), 0, 8 ) ),
                    );
                    $self->add_auth_header($header);
                }
            }
        }

        # the alleged author of the email may specify how to handle email
        if (   $config->{'check_adsp'}
            && ( $self->is_local_ip_address() == 0 )
            && ( $self->is_trusted_ip_address() == 0 )
            && ( $self->is_authenticated() == 0 ) )
        {
            foreach my $policy ( $dkim->policies() ) {
                my $apply    = $policy->apply($dkim);
                my $string   = $policy->as_string();
                my $location = $policy->location() || q{};
                my $name     = $policy->name();
                my $default  = $policy->is_implied_default_policy();

                my $otype = ref $policy;
                my $type =
                    $otype eq 'Mail::DKIM::AuthorDomainPolicy' ? 'dkim-adsp'
                  : $otype eq 'Mail::DKIM::DkimPolicy'         ? 'x-dkim-ssp'
                  : $otype eq 'Mail::DKIM::DkPolicy'           ? 'x-dkim-dkssp'
                  :   'x-dkim-policy';

                $self->dbgout( 'DKIMPolicy',         $apply,                  LOG_DEBUG );
                $self->dbgout( 'DKIMPolicyString',   $string,                 LOG_DEBUG );
                $self->dbgout( 'DKIMPolicyLocation', $location,               LOG_DEBUG );
                $self->dbgout( 'DKIMPolicyName',     $name,                   LOG_DEBUG );
                $self->dbgout( 'DKIMPolicyDefault',  $default ? 'yes' : 'no', LOG_DEBUG );

                my $result =
                    $apply eq 'accept'  ? 'pass'
                  : $apply eq 'reject'  ? 'discard'
                  : $apply eq 'neutral' ? 'unknown'
                  :                       'unknown';

                if ( ! ( $config->{'adsp_hide_none'} && $result eq 'none' ) ) {
                    if ( ( ! $default ) or $config->{'show_default_adsp'} ) {
                        my $comment = '('
                          . $self->format_header_comment( ( $default ? 'default ' : q{} )
                            . "$name policy"
                            . ( $location ? " from $location" : q{} )
#                            . ( $string   ? "; $string"       : q{} )
                          )
                          . ')';

                        my $header = join( q{ },
                            $self->format_header_entry( $type, $result ), $comment, );
                        $self->add_auth_header( $header );
                    }
                }
            }
        }
    };
    if ( my $error = $@ ) {

        # Also in DMARC module
        $self->log_error( 'DKIM EOM Error ' . $error );
        $self->_check_error( $error );
        $self->{'failmode'} = 1;
        return;
    }
}

sub close_callback {
    my ( $self ) = @_;
    delete $self->{'failmode'};
    delete $self->{'headers'};
    delete $self->{'body'};
    delete $self->{'carry'};
    delete $self->{'has_dkim'};
    $self->destroy_object('dkim');
    return;
}

sub _check_error {
    my ( $self, $error ) = @_;

    if ( $error =~ / on an undefined value at /
            or $error =~ / as a HASH ref while /
            or $error =~ / as an ARRAY reference at /
            or $error =~ / as a subroutine ref while /
            or $error =~ / on unblessed reference at /
            or $error =~ /^Cannot convert a reference to /
            or $error =~ /^Not a HASH reference at /
            or $error =~ /^Not a CODE reference at /
            or $error =~ /^Cannot copy to HASH in sassign at /
            or $error =~ /^Cannot copy to ARRAY in sassign at /
            or $error =~ /^Undefined subroutine /
            or $error =~ /^invalid protocol/
            or $error =~ / locate object method /
            or $error =~ /^panic: /
    ) {
        $self->log_error( "PANIC DETECTED: in DKIM method: $error" );
        $self->exit_on_close();
        $self->tempfail_on_error();
        $self->add_auth_header('dkim=temperror (internal error)');

        delete $self->{'headers'};
        return;
    }
    elsif ( $error =~ /^DNS error: query timed out/
            or $error =~ /^DNS query timeout/
    ){
        $self->log_error( 'Temp DKIM Error - ' . $error );
        $self->add_auth_header('dkim=temperror (dns timeout)');
    }
    elsif ( $error =~ /^no domain to fetch policy for$/
            or $error =~ /^policy syntax error$/
            or $error =~ /^empty domain label/
            or $error =~ /^invalid name /
    ){
        $self->log_error( 'Perm DKIM Error - ' . $error );
        $self->add_auth_header('dkim=permerror (syntax or domain error)');
    }
    else {
        $self->log_error( 'Unexpected DKIM Error - ' . $error );
        $self->add_auth_header('dkim=temperror');
        # Fill these in as they occur, but for unknowns err on the side of caution
        # and tempfail/exit
        $self->exit_on_close();
        $self->tempfail_on_error();
    }
    return;
}

1;

__END__

=head1 NAME

  Authentication Milter - DKIM Module

=head1 DESCRIPTION

Module for validation of DKIM and DomainKeys signatures, and application of ADSP policies.

=head1 CONFIGURATION

        "DKIM" : {                                      | Config for the DKIM Module
            "hide_none"         : 0,                    | Hide auth line if the result is 'none'
            "check_adsp"        : 1,                    | Also check for ADSP
            "show_default_adsp" : 0,                    | Show the default ADSP result
            "adsp_hide_none"    : 0                     | Hide auth ADSP if the result is 'none'
        },

=head1 SYNOPSIS

=head1 AUTHORS

Marc Bradshaw E<lt>marc@marcbradshaw.netE<gt>

=head1 COPYRIGHT

Copyright 2015

This library is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.


