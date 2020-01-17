#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

my $out = qx{perl ./bin/jobtemplate-convert.pl --help};
my $usage = "```\n$out```\n";

open my $fh, '<', 'README.md' or die $!;
my $readme = do { local $/; <$fh> };
close $fh;

$readme =~ s/^## Usage.*/## Usage\n\n$usage/ms;

open $fh, '>', 'README.md' or die $!;
print $fh $readme;
close $fh;

say "Updated README.md";
