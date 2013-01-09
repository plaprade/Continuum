#!/usr/bin/env perl
use strict;
use warnings;

use File::Slurp;

my $text = `pod2markdown < lib/AnyEventX/CondVar/Readme.pm`;

my $l = '\n[ ]{4}[^\n]*';
my $e = '\n[ ]*';
$text =~ s/($l($l|$e)*$l\n)/\n```perl$1```\n/gs;

open( FH, '>README.md' );
print FH $text;
close( FH );
