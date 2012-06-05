#---------------------------------------------------------------------------------------------------
# Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
# Contact: http://www.qt-project.org/
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE from this package for details.
#
# Following Perl modules are needed
#     CGI::FormBuilder
#     CGI::FormBuilder::Source::File
#     CGI::FormBuilder::Mail::FormatMultiPart
#---------------------------------------------------------------------------------------------------

package CGI::FormBuilder::Mail::reltestmailer;

use strict;
use warnings;
use Data::Dumper;

require MIME::Types;  # for MIME::Lite's AUTO type detection - required
require MIME::Lite;

our $VERSION = 1.000006;

use English '-no_match_vars;';

use CGI::FormBuilder::Util;
use CGI::FormBuilder::Field;

use Regexp::Common qw( net );

sub new {
    my $class = shift;
    my $self = { @_ };

    bless $self, $class;
    return $self;
}

sub mailresults {
    my ($self) = @_;

    my $form = $self->{form};
    puke "No CGI::FormBuilder passed as form arg"
        if !$form || !$form->isa('CGI::FormBuilder');

    my ($subject, $to, $cc, $bcc, $from, $smtp )
        = @{$self}{qw( subject to cc bcc from smtp )};

    puke "Address/subject args should all be scalars"
        if scalar grep { defined && ref }
            ( $to, $from, $smtp, $cc, $bcc, $subject );

    puke "Cannot send mail without to, from, and smtp args"
        if  !$to || !$from || !$smtp;

    puke "arg 'smtp' in bad format"
        if !(   $smtp eq 'localhost'
            ||  $smtp =~ m{ \A $RE{net}{domain}{-nospace} \z }xms
            ||  $smtp =~ m{ \A $RE{net}{IPv4} \z }xms
            )
        ;

    # let MIME::Lite check e-mail address or address list format
    # (VALIDATE pattern for multiple addresses too much of a pain)

    my ($format, $skipfields, $skip ) = @{$self}{qw( format skipfields skip )};

    # set up a hash of the individual CGI::FormBuilder::Field objects and
    # put it into $self to pass around.  it's useful.
    my $fbflds = $self->{_fbflds} = { map { ( "$_" => $_ ) } $form->field };

    my $msg = undef;
    my %msg_args = (
        From        => $from,
        To          => $to,
        Subject     => $subject,
        Type        => "text/plain",
    );
    $msg_args{Cc}  = $cc       if defined $cc;
    $msg_args{Bcc} = $bcc      if defined $bcc;

    $msg_args{Data} = $self->format_content();
    $msg = MIME::Lite->new( %msg_args );

    my $success = eval $msg->send_by_smtp( $smtp );
#    my $success = eval $msg->print(\*STDOUT);

    if ($EVAL_ERROR || !$success) {
        puke("Could not send mail. $EVAL_ERROR");
    }

    return;
}

sub format_content
{
    my ($self) = @_;

    my $text = '';

    my $data_form = $self->_data_form();

    my $maxlen = 0;
    for (@{$data_form}[ 1 .. $#{$data_form} ]) {
        my @data = @{$_};
        $maxlen = length($data[0]) if (length($data[0]) > $maxlen);
    }

    # +12 for column spacing and 'DD/MM/YYYY'
    my $sep = '-' x ($maxlen + 12);

    for (@{$data_form}[ 1 .. $#{$data_form} ]) {
        my @data = @{$_};
        if ($data[0] eq 'Comments') {
            $text .= "$data[0]:\n$data[1]\n\n";
        } elsif ($data[1] eq '') {
            $data[0] =~ s/\<hr\>/$sep\n/;
            $data[0] =~ s/\<\S+\>//g;
            $text .= $data[0] . "\n$sep\n";
        } else {
            $data[0] =~ s/\<\S+\>//g;
            $text .= "$data[0]:" . (' ' x ($maxlen - length($data[0]))) . " $data[1]\n";
        }
    }

    my $http_host   = $ENV{'HTTP_HOST'};
    my $request_uri = $ENV{'REQUEST_URI'};
    my $remote_addr = $ENV{'REMOTE_ADDR'};
    $text .= "\n-- \nReport";
    $text .= " form at http://$http_host$request_uri" if (defined $http_host && defined $request_uri);
    $text .= " submitted from $remote_addr" if (defined $remote_addr);
    $text .= " from unknown source" if (!defined $request_uri && !defined $remote_addr);
    $text .= "\n";

    return $text;
}

sub _data_resolve_options {
    my ($self, $name, @options) = @_;
    my @result;

    my $form = $self->{'form'};
    my $opts = $form->{'fieldopts'}->{$name}->{'options'};
    return @result if (!defined $opts);

    # Options are arrays of arrays
    my %hash;
    foreach my $item (@{$opts}) {
        $hash{@{$item}[0]} = @{$item}[1];
    }
    foreach my $val (@options) {
        push @result, $hash{$val};
    }
    return @result;
}

sub _data_form {
    my ($self) = @_;
    my ($form, $fbflds) = @{$self}{qw( form _fbflds )};
    my @field_names = $form->fields;

    my $data = [
        [ 'Field' => 'Value' ]
    ];

    FIELD:
    foreach my $name ( @field_names ) {
        next FIELD if $fbflds->{$name}->type eq 'file';
        my @values = $form->field($name);
        @values = $self->_data_resolve_options($name, @values)
            if(defined $form->{'fieldopts'}->{$name}->{'options'});
        my $value = join(", ",@values);
        $value = '' if (!$value);

        my $labels = $form->{'fieldopts'}->{$name}->{'label'};
        my $label = $labels;
        if (ref($labels) eq 'ARRAY') {
            $label = join (', ', @{$labels});
        }
        $label = $name if ($label eq '');

        push @{$data}, [ $label => $value ];
    }

    # cache in self
    $self->{_data_form} = $data;
    return $data;
}

1;
