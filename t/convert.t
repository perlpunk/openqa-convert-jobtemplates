#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use FindBin '$Bin';

use lib "$Bin/../local/lib/perl5";
use JobTemplate qw/ inline_testsuite /;

my $dir = "$Bin/data";
my $template_file = "$dir/demo-template.yaml";
my $testsuite_file = "$dir/demo-testsuite.json";
my $output = inline_testsuite(
    template => $template_file,
    testsuite => [$testsuite_file],
    convert_multi => 1,
);

my $expected1 = do {
    open my $fh, '<', "$dir/demo-template.yaml.expected1" or die $!;
    local $/; <$fh>;
};
my $expected2 = do {
    open my $fh, '<', "$dir/demo-template.yaml.expected2" or die $!;
    local $/; <$fh>;
};
my $ok = cmp_ok($output, 'eq', $expected1, "Converted template ok");
unless ($ok) {
    show_diff($template_file, $output, $expected1);
}


$output = inline_testsuite(
    template => $template_file,
    testsuite => [$testsuite_file],
    convert_multi => 1,
    empty_only => 1,
);

$ok = cmp_ok($output, 'eq', $expected2, "Converted template ok");
unless ($ok) {
    show_diff($template_file, $output, $expected2);
}


sub show_diff {
    my ($template_file, $output, $expected) = @_;
    my $file1 = "$template_file.expected";
    my $file2 = "$template_file.new";
    open my $fh, '>', $file1 or die $!;
    print $fh $expected;
    close $fh;
    open $fh, '>', $file2 or die $!;
    print $fh $output;
    close $fh;
    my $diffcmd = "colordiff -u5 $file1 $file2";
    system $diffcmd;
    unlink $file1;
    unlink $file2;
}

done_testing;
