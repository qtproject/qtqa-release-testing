#!/usr/bin/perl

#---------------------------------------------------------------------------------------------------
# Copyright (C) 2013 Digia Plc and/or its subsidiary(-ies).
# Contact: http://www.qt-project.org/legal
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE from this package for details.
#
# Following Perl modules are needed
#     CGI::FormBuilder
#     CGI::FormBuilder::Source::File
#     CGI::FormBuilder::Mail::FormatMultiPart
#---------------------------------------------------------------------------------------------------

# Add current dir to be able to load our own custom mailer 'reltestmailer'
use Cwd;
push @INC, cwd;

use POSIX qw(strftime);
use CGI::FormBuilder;
use Data::Dumper;

sub meaning
{
    my ($form, $field_name) = @_;

    my $val = $form->field->{$field_name};
    return $val if (!defined $form->{'fieldopts'}->{$field_name}->{'options'});

    my $result = "Not tested";
    $result = "Yes" if ($val = 2);
    $result = "No" if ($val = 1);
    return $result;
}

# First create our form
my $form = CGI::FormBuilder->new(source => 'reltest-form.conf');

# Check to see if we're submitted and valid
if ($form->submitted && $form->validate) {

    our $field = $form->fields;

    # Translate options over to values
    our %result;
    for my $val (keys %{$field}) {
        $result{$val} = meaning($form, $val);
    }

    # Show confirmation screen
    print $form->confirm(header => 1);

    # Mail off a copy to the mailing list
    $form->mailresults(plugin  => 'reltestmailer',
                       from    => $field->{'report_name'} . '<releasing@qt-project.org>',
                       to      => 'Releases Mailing List <releasing@qt-project.org>',
                       smtp    => 'mx.qt-project.org',
                       subject => "Testing: $field->{'package_date'} + $field->{'mkspec_used'} " .
                                  ($field->{'releasable'} == 2 ? '[success!]' : '[fail]')
                       );
} else {
    # Auto-fill with today's date

    my $now = strftime("%m/%d/%Y", localtime);
    $form->field(name => 'report_date',
                 value => $now);
    $form->field(name => 'package_date',
                 value => $now);

    # Print out the form
    print $form->render(header => 1);
}
