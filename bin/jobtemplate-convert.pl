#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use FindBin '$Bin';
use File::Basename qw/ basename /;
use lib "$Bin/../local/lib/perl5";
use lib "$Bin/../lib";
use JobTemplate qw/ inline_testsuite fetch_testsuite fetch_jobtemplate /;
use Data::Dumper;
use Getopt::Long::Descriptive;
use File::Path qw(make_path);

my $basename = basename $0;
my ($opt, $usage) = describe_options(
    <<"EOM",
 $basename %o <jobtemplate-id> <testsuite-ids>

 e.g.
 $basename --host o3 34 1195 1196
EOM
    [ 'host=s',        'OpenQA host (e.g. o3, osd or localhost)', { required => 1 } ],
    [ 'apikey=s',      'API Key', { required => 1 } ],
    [ 'apisecret=s',   'API Secret', { required => 1 } ],
    [ 'convert-multi', 'Also convert if testsuite is contained multiple times' ],
    [ 'empty-only',    'Only convert plain "- name" testsuite entries, not existing settings' ],
    [ 'help',          "print usage message and exit", { shortcircuit => 1 } ],
);
print($usage->text), exit if $opt->help;
my %hosts = (
    o3        => "https://openqa.opensuse.org",
    osd       => "https://openqa.suse.de",
    localhost => "http://localhost",
);

my $host = $opt->host;
my $host_url = $hosts{ $host }
    or die "Could not find host $host (must be o3, osd or localhost)";
my $data = "$Bin/../data/$host";
make_path("$data/testsuites");
make_path("$data/jobtemplates");

my ($jt, @ts) = @ARGV;
my $template_file  = "$data/jobtemplates/$jt.yaml";
my @testsuite_files = map { "$data/testsuites/$_.json" } @ts;

my %options = (
    host_url => $host_url,
    apikey => $opt->apikey,
    apisecret => $opt->apisecret,
);
for my $ts (@ts) {
    fetch_testsuite($data, $ts, %options);
}
fetch_jobtemplate($data, $jt, %options);

my $output = inline_testsuite(
    template => $template_file,
    testsuite => \@testsuite_files,
    convert_multi => $opt->convert_multi,
    empty_only => $opt->empty_only,
);
unless (length $output) {
    exit;
}
open my $fh, '>:encoding(UTF-8)', "$template_file.new" or die $!;
print $fh $output;
close $fh;

say "Created $template_file.new";
my $diff = "/tmp/diff-$jt.diff";
my $diffcmd = "colordiff -u999 $template_file* >$diff";
my $rc = system($diffcmd);
unless ($rc) {
    say "Nothing changed";
    unlink $diff;
    exit;
}
$rc = system("less $diff");
unlink $diff;
my $out = qx{openqa-validate-yaml $template_file.new 2>&1};
if ($?) {
    say "Validation of new file failed:\n$out";
    exit 1;
}
say "Validation of new file passed";


exit;
