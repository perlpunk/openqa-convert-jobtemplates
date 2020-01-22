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

my $expected = <<'EOM';
products:
  opensuse-Tumbleweed-DVD-s390x:
    distri: opensuse
    flavor: DVD
    version: Tumbleweed
scenarios:
  s390x:
    opensuse-Tumbleweed-DVD-s390x:
    - textmode-server:   # insert description and new settings
         description: testsuite description
         testsuite: empty
         settings:
           DESKTOP: textmode
           EXTRABOOTPARAMS: hvc_iucv=8
           EXTRABOOTPARAMS2: hvc_iucv=9
           FILESYSTEM: xfs
    - textmode-server:   # insert description and merged settings
         description: testsuite description
         testsuite: empty
         settings:
             DESKTOP: textmode
             FILESYSTEM: btrfs
    - textmode-server:   # insert settings
       settings:
         DESKTOP: textmode
         FILESYSTEM: xfs
       testsuite: empty
       description: foo
    - textmode-server:   # insert description and settings
        settings:
          DESKTOP: textmode
          FILESYSTEM: xfs
        description: testsuite description
        testsuite: empty
        priority: 99
    - textmode-server:    # append testsuite
        description: testsuite description
        settings:
          DESKTOP: textmode
          FILESYSTEM: xfs
        testsuite: empty
    - foo

EOM
my $ok = cmp_ok($output, 'eq', $expected, "Converted template ok");
unless ($ok) {
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
