package JobTemplate;
use warnings;
use strict;
use 5.010;

use base 'Exporter';
our @EXPORT_OK = qw/
    inline_testsuite fetch_testsuite fetch_jobtemplate
    post_jobtemplate
/;

use YAML::LibYAML::API::XS;
use YAML::PP;
use YAML::PP::Common;
use File::Path qw(make_path);
use JSON::PP;
use Storable 'dclone';

use constant DEBUG => $ENV{DEBUG} ? 1 : 0;

sub inline_testsuite {
    my %args = @_;

    my $yp = YAML::PP->new( schema => [qw/ Core /] );
    my $template_file = $args{template};
    my $testsuite_files = $args{testsuite};
    my $convert_multi = $args{convert_multi};
    my $empty_only = $args{empty_only};

    my @testsuites = map {
        my $data       = $yp->load_file($_);
        my $list = $data->{TestSuites} or die "No TestSuites";
        $list->[0];
    } @$testsuite_files;
    my %names = map { $_->{name} => 0 } @testsuites;

    my $template = $yp->load_file($template_file);
    my $found_testsuites = 0;
    my $archs = $template->{scenarios};
    for my $arch (sort keys %$archs) {
        my $products = $archs->{ $arch };
        for my $product (sort keys %$products) {
            my $suites = $products->{ $product };
            for my $suite (@$suites) {
                my $name;
                if (ref $suite eq 'HASH') {
                    ($name, my $value) = %$suite;
                    if ($value->{testsuite}) {
                        # test suite name defined by 'testsuite' key
                        # not supported currently
                        $name = '';
                    }
                }
                else {
                    $name = $suite;
                }
                if (exists $names{ $name }) {
                    $names{ $name }++;
                    $found_testsuites++;
                }
            }
        }
    }
    if ($found_testsuites == 0) {
        say "No matching testsuites found in template";
        return '';
    }
    if (not $convert_multi) {
        for my $name (sort keys %names) {
            if ($names{ $name } > 1) {
                say "Testsuite $name contained multiple times";
                delete $names{ $name };
            }
        }
    }
    @testsuites = grep { ($names{ $_->{name} } || 0) >= 1 } @testsuites;
    unless (@testsuites) {
        return '';
    }

    open my $fh, '<:encoding(UTF-8)', $template_file or die $!;
    my @lines = <$fh>;
    close $fh;
    my @events = parse_events($template_file);

    for my $testsuite (@testsuites) {
        say "Processing $testsuite->{name}";
        my $settings = $testsuite->{settings};
        my %settings = map {
            my $value = $_->{value};
            $value =~ s/ +$//; # remove trailing spaces
            $_->{key} => $value;
        } @$settings;
        $testsuite->{settings} = \%settings;
        $testsuite->{description} //= '';
        $testsuite->{description} =~ s/ +$//; # remove trailing spaces
        my @local_events = @events;
        while (1) {
            my ($found) = search_testsuite(
                \@lines, \@local_events, $testsuite,
                empty_only => $empty_only,
            );
            last unless $found;
        }
    }
    return join '', @lines;
}

sub search_testsuite {
    my ($lines, $items, $ts, %args) = @_;
    $ts = dclone($ts);
    my $empty_only = $args{empty_only};
    my $name     = $ts->{name};
    return unless @$items;
    my $tline = 0;
    my $tcol  = 0;
    while (my $ev = shift @$items) {
        my $event = $ev->{event};
        my $types = $ev->{types};
        my $count = $ev->{count};
        my $level = $ev->{level};
        pp($ev);
        # testsuite keys are only on levels 3 (sequence) or 4 (mapping)
        next unless ($level == 3 or $level == 4);
        # we only search for scalar events
        unless ($event->{name} eq 'scalar_event' and $event->{value} eq $name) {
            next;
        }


        my $found_key = ($types->[$level] eq 'MAP' and $count->[$level] == 1);
        my $found_seq = $types->[$level] eq 'SEQ';
        if ($found_key) {
            say "========= KEY $level $name" if DEBUG;
            if ($empty_only) {
                say "Found '$name:' entry, but only processing empty '- $name' entries. Skip";
                next;
            }
            my $found_settings = 0;
            my $found_description;
            $tline = $event->{start}->{line};
            $tcol  = $event->{start}->{column};
            my $next_map = $items->[0]->{event};
            my $next_value = $items->[1]->{event};
            if ($next_map->{name} eq 'alias_event') {
                say "We got an *alias, skipping";
                return 1;
            }
            my $map_col  = $next_value->{start}->{column};
            my @ts_events;
            while ($items->[0]->{level} > $level) {
                push @ts_events, shift @$items;
            }
            while (my $ev = shift @ts_events) {
                pp($ev);
                next unless $ev->{level} == $level + 1;
                next if $ev->{event}->{name} ne 'scalar_event';
                if ($ev->{event}->{value} eq 'settings') {
                    my $settings_level = $ev->{level};
                    say "========= SEQ $settings_level settings" if DEBUG;
                    my $sline           = $ev->{event}->{start}->{line};
                    my $next_map        = $ts_events[0]->{event};
                    my $map_col         = $next_map->{start}->{column};

                    my @settings_events;
                    my $start_line;
                    my $end_line;
                    while (my $ev = shift @ts_events) {
                        if ($ev->{event}->{name} eq 'mapping_start_event') {
                            next;
                        }
                        if ($ev->{event}->{name} eq 'mapping_end_event') {
                            last;
                        }
                        $start_line ||= $ev->{event}->{start}->{line};
                        $end_line = $ev->{event}->{end}->{line};
                        pp($ev);
                    }
                    my $yaml = join '', @$lines[ $start_line .. $end_line ];
                    $lines->[ $_ ] = '' for $start_line .. $end_line;
                    my $append_settings = inline_yaml($map_col, $ts->{settings}, $yaml);

                    say "Appending settings to existing '$name:' entry";
                    $lines->[$sline] .= $append_settings;
                    $found_settings = 1;

                }
                elsif ($ev->{event}->{value} eq 'description') {
                    say "========= SEQ $level description" if DEBUG;
                    # description here will overwrite testsuite description,
                    # nothing to do
                    $found_description = 1;
                }
            }
            unless ($found_settings) {
                my $append_settings = inline_yaml($map_col + 2, $ts->{settings});
                $append_settings = (' ' x ($map_col)) . "settings:\n" . $append_settings;

                say "Inserting settings into '$name:' entry";
                $lines->[$tline] .= $append_settings;
            }
            unless ($found_description) {
                my $desc_yaml = inline_yaml($map_col, {description => $ts->{description}});

                say "Inserting description into '$name:' entry";
                $lines->[$tline] .= $desc_yaml;
            }

            my $yaml = inline_yaml($map_col, {testsuite => undef},);
            say "Inserting 'testsuite: null' into '$name:' entry";
            $lines->[$tline] .= $yaml;
            return $found_key;
        }
        elsif ($found_seq) {
            say "========= SEQ $level $name" if DEBUG;
            $tline = $event->{start}->{line};
            $tcol  = $event->{start}->{column};
            $lines->[$tline] =~ s/(?<=\Q$name\E)/:/;
            my $line    = $lines->[$tline];
            my $ts_yaml = ts_yaml($ts);
            $ts_yaml =~ s/^/' ' x ($tcol + 2)/meg;

            say "Appending test suite to '$name' entry";
            $lines->[$tline] .= $ts_yaml;
            return 1;
        }
    }
    return;
}

sub parse_events {
    my ($template_file) = @_;
    my $parse_events = [];
    YAML::LibYAML::API::XS::parse_file_events($template_file, $parse_events);
    my $level = -1;
    my @types;
    my @count;
    my @events;
    while (my $event = shift @$parse_events) {
        next if $event->{name} =~ m/^(stream|doc)/;
        my $str = YAML::PP::Common::event_to_test_suite($event);
        if ($str =~ m/^(\+(MAP|SEQ)|=VAL)/ and $level >= 0) {
            $count[$level]++;
        }
        if ($str =~ m/^\+/) {
            $level++;
        }
        if ($str =~ m/^\+(MAP|SEQ)/) {
            $types[$level] = $1;
        }
        push @events,
          {
            event => $event,
            types => [@types],
            count => [@count],
            level => $level,
          };

        if ($str =~ m/^-/) {
            $level--;
            pop @types;
            pop @count;
        }
    }
    return @events;
}


sub ts_yaml {
    my ($ts)     = @_;
    my %data     = (
        testsuite   => undef,
        description => $ts->{description},
        settings    => $ts->{settings},
    );
    my $yaml = YAML::PP->new(header => 0, schema => [qw/ Core /])->dump_string(\%data);
    return $yaml;
}


sub inline_yaml {
    my ($indent, $data, $existing_yaml) = @_;
    my $yp = YAML::PP->new(header => 0, schema => [qw/ Core /]);
    if ($existing_yaml) {
        my $existing = $yp->load_string($existing_yaml);
        %$data = (
            %$data,
            %$existing,
        );
    }
    my $yaml = $yp->dump_string($data);
    $yaml =~ s/^/' ' x ($indent)/meg;
    return $yaml;
}

sub fetch_testsuite {
    my ($data, $id, %args) = @_;
    my $host_url = $args{host_url};
    my $apikey = $args{apikey};
    my $apisecret = $args{apisecret};
    make_path("$data/testsuites");
    my $file = "$data/testsuites/$id.json";
    unless (-e $file) {
        say "Fetching $file";
        my $arg;
        if ($id =~ tr/0-9//c) {
            $arg = "name=$id";
        }
        else {
            $arg = "id=$id";
        }
        my $cmd
          = sprintf "openqa-client --host %s --json-output test_suites get '%s' >%s",
          $host_url, $arg, $file;
        system $cmd;
        if ($?) {
            warn "Cmd '$cmd' failed";
            exit 1;
        }
    }
}

sub fetch_jobtemplate {
    my ($data, $id, %args) = @_;
    my $host_url = $args{host_url};
    my $apikey = $args{apikey};
    my $apisecret = $args{apisecret};
    make_path("$data/jobtemplates");
    my $file = "$data/jobtemplates/$id.yaml";
    unless (-e $file) {
        say "Fetching $file";
        my $cmd
          = sprintf "curl %s/api/v1/job_templates_scheduling/%s >%s",
          $host_url, $id, $file;
        system $cmd;
        if ($?) {
            warn "Cmd '$cmd' failed";
            exit 1;
        }
    }
}

sub post_jobtemplate {
    my %args = @_;
    my $id = $args{id} or die "Job template ID required";
    my $file = $args{file};
    my $apikey = $args{apikey} or die "API key required";
    my $apisecret = $args{apisecret} or die "API secret required";
    my $host_url = $args{host};

    open my $fh, '<', $file or die "Could not open '$file': $!";
    my $yaml = do { local $/; <$fh> };
    close $fh;
    $yaml =~ s/"/\\"/g;

    my $preview = 1;
    my $cmdfmt = 'openqa-client --host %s --apikey=%s --apisecret=%s job_templates_scheduling/%s post --json-output --form schema=JobTemplates-01.yaml preview=%s template="%s"';
    my $_cmd = sprintf $cmdfmt,
        $host_url, '$key', '$secret', $id, $preview, '$template';
    say "Preview (Command: $_cmd)";
    my $cmd = sprintf $cmdfmt,
        $host_url, $apikey, $apisecret, $id, $preview, $yaml;
    my $out = qx{$cmd};
    say "Response:\n$out\n";
    my $json = decode_json($out);
    unless ($json->{changes}) {
        say "No changes";
        return;
    }
    say "Changes:";
    say $json->{changes};

    print "Post (press Enter)";
    my $enter = <STDIN>;
    $preview = 0;
    $_cmd = sprintf $cmdfmt,
        $host_url, '$key', '$secret', $id, $preview, '$template';
    say "Command: $_cmd";
    $cmd = sprintf $cmdfmt,
        $host_url, $apikey, $apisecret, $id, $preview, $yaml;
    $out = qx{$cmd};
    say "Response:\n$out\n";
    $json = decode_json($out);
    unless ($json->{changes}) {
        say "No changes";
        return;
    }
    say "Changes:";
    say $json->{changes};

    say "Successfully posted new template";
    open $fh, '>', "$file.posted" or die $!;
    say $fh "Posted successfully";
    close $fh;

}

sub pp {
    my ($ev) = @_;
    return unless DEBUG;
    my $event = $ev->{event};
    my $str   = YAML::PP::Common::event_to_test_suite($event);
    say sprintf "%-20s %-35s L:%2d C:%2d %-30s %-30s",
      (' ' x ($ev->{level} * 2)) . "$ev->{level}|", $str,
      $event->{start}->{line}, $event->{start}->{column},
      "@{ $ev->{types} }", "@{ $ev->{count} }";
}


1;
