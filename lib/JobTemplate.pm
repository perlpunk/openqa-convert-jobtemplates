package JobTemplate;
use warnings;
use strict;
use 5.010;

use base 'Exporter';
our @EXPORT_OK = qw/ inline_testsuite fetch_testsuite fetch_jobtemplate /;

use YAML::LibYAML::API::XS;
use YAML::PP;
use YAML::PP::Common;

use constant DEBUG => $ENV{DEBUG} ? 1 : 0;

sub inline_testsuite {
    my %args = @_;

    my $yp = YAML::PP->new;
    my $template_file = $args{template};
    my $testsuite_file = $args{testsuite};
    my $convert_multi = $args{convert_multi};

    my $testsuite = do {
        my $data       = $yp->load_file($testsuite_file);
        my $testsuites = $data->{TestSuites} or die "No TestSuites";
        $testsuites->[0];
    };

    my $template = $yp->load_file($template_file);
    my $found_testsuite = 0;
    my $archs = $template->{scenarios};
    for my $arch (sort keys %$archs) {
        my $products = $archs->{ $arch };
        for my $product (sort keys %$products) {
            my $suites = $products->{ $product };
            for my $suite (@$suites) {
                my $name;
                if (ref $suite eq 'HASH') {
                    ($name) = keys %$suite;
                }
                else {
                    $name = $suite;
                }
                if ($name eq $testsuite->{name}) {
                    $found_testsuite++;
                }
            }
        }
    }
    if ($found_testsuite == 0) {
        say "Testsuite $testsuite->{name} not found in template";
        return '';
    }
    if ($found_testsuite > 1 and not $convert_multi) {
        say "Testsuite $testsuite->{name} contained multiple times";
        return '';
    }

    open my $fh, '<:encoding(UTF-8)', $template_file or die $!;
    my @lines = <$fh>;
    close $fh;
    my @events = parse_events($template_file);

    while (1) {
        my ($found) = JobTemplate::search_testsuite(\@lines, \@events, $testsuite);
        last unless $found;
    }
    return join '', @lines;
}

sub search_testsuite {
    my ($lines, $items, $ts) = @_;
    my $name     = $ts->{name};
    my $settings = $ts->{settings};
    my %settings = map { $_->{key} => $_->{value} } @$settings;
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
                    my $append_settings = inline_yaml($map_col, \%settings, $yaml);

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
                my $append_settings = inline_yaml($map_col + 2, \%settings,);
                $append_settings = (' ' x ($map_col)) . "settings:\n" . $append_settings;

                say "Inserting settings into '$name:' entry";
                $lines->[$tline] .= $append_settings;
            }
            unless ($found_description) {
                my $desc_yaml = inline_yaml($map_col, {description => $ts->{description}},);

                say "Inserting description into '$name:' entry";
                $lines->[$tline] .= $desc_yaml;
            }

            my $yaml = inline_yaml($map_col, {testsuite => 'empty'},);
            say "Inserting 'testsuite: empty' into '$name:' entry";
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
    my $settings = delete $ts->{settings};
    my %settings = map { $_->{key} => $_->{value} } @$settings;
    my %data     = (
        testsuite   => 'empty',
        description => $ts->{description},
        settings    => \%settings,
    );
    my $yaml = YAML::PP->new(header => 0)->dump_string(\%data);
    return $yaml;
}


sub inline_yaml {
    my ($indent, $data, $existing_yaml) = @_;
    my $yp = YAML::PP->new(header => 0);
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
    my $file = "$data/testsuites/$id.json";
    unless (-e $file) {
        say "Fetching $file";
        my $cmd
          = sprintf "openqa-client --host %s --apikey=%s --apisecret=%s --json-output test_suites/%d get >%s",
          $host_url, $apikey, $apisecret, $id, $file;
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
    my $file = "$data/jobtemplates/$id.yaml";
    unless (-e $file) {
        say "Fetching $file";
        my $cmd
          = sprintf
"openqa-client --host %s --apikey=%s --apisecret=%s job_templates_scheduling/%s get | jq --raw-output . >%s",
          $host_url, $apikey, $apisecret, $id, $file;
        system $cmd;
        if ($?) {
            warn "Cmd '$cmd' failed";
            exit 1;
        }
    }
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