#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;
use utf8;

use JSON qw( encode_json decode_json );
use LWP::UserAgent;
use File::Temp qw(tempfile);

my $ua = LWP::UserAgent->new( timeout => 10 );
my $item_key = $ENV{SRV_ITEM_KEY};

my %CHECK_MAP = ( passing => 0, warning => 1, critical => 2 );

my @dcs;
my @nodes;
my @services;
my @checks;
my @services_flow;
my @checks_flow;

my @items_data;

my %check_exists;
my %services_count;

_dcs();

my $zabbix = "zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME}";

my $val = encode_json( { data => \@dcs } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_dcs' -o '$val'`;

$val = encode_json( { data => \@nodes } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_nodes' -o '$val'`;

$val = encode_json( { data => \@services } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_services' -o '$val'`;

$val = encode_json( { data => \@services_flow } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_services_flow' -o '$val'`;

$val = encode_json( { data => \@checks } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_checks' -o '$val'`;

$val = encode_json( { data => \@checks_flow } );
say `$zabbix -k '$ENV{SRV_DISCOVERY_KEY}_checks_flow' -o '$val'`;

my ( $fh, $filename ) = tempfile();
binmode $fh, ':utf8';
print $fh @items_data;
close $fh;

say `$zabbix -i $filename`;

sub _query {
  my $addr = shift;

  my $url  = "http://$ENV{CONSUL_HTTP_ADDR}$addr";
  my $resp = $ua->get($url);

  unless ( $resp->is_success ) {
    warn 'Consul unacessible';
    return;
  }

  return decode_json( $resp->decoded_content );
}

sub _dcs {
  my $data = _query('/v1/catalog/datacenters');
  return unless $data;

  foreach my $dc (@$data) {
    push @dcs, { '{#DC}' => $dc };
    push @items_data, "- ${item_key}_dc_status[$dc] 1\n";

    _nodes($dc);
  }

  foreach my $key ( keys %services_count ) {
    push @items_data,
        "- ${item_key}_service_flow_count[$key] $services_count{$key}{count}\n";
    push @items_data,
        "- ${item_key}_service_flow_setuped_count[$key] $services_count{$key}{setuped_count}\n";
  }

  return;
}

sub _nodes {
  my $dc = shift;

  my $data = _query("/v1/catalog/nodes?dc=$dc");
  return unless $data;

  foreach my $node (@$data) {
    my $item = {
      '{#DC}'   => $dc,
      '{#NODE}' => $node->{Node},
    };
    push @nodes,      $item;
    push @items_data, "- ${item_key}_node_status[$dc,$node->{Node}] 1\n";
    _services( $dc, $node );
  }

  return;
}

sub _services {
  my ( $dc, $node ) = @_;

  my $data = _query("/v1/catalog/node/$node->{Node}?dc=$dc");
  return unless $data;

  foreach my $service ( values %{ $data->{Services} } ) {
    $service->{ID} = _service_prettify( $service->{ID}, $service->{Tags} );

    my $count = _detect_count( $service->{Tags} );

    if ( _is_ignore( $service->{Tags} ) ) {
      _checks( $dc, $node, $service, $count );
      next;
    }

    if ($count) {
      my $item = { '{#SERVICE_ID}' => $service->{ID} };

      push @services_flow, $item;

      my $key = $service->{ID};
      $services_count{$key} //= { count => 0, setuped_count => $count };
      $services_count{$key}{count}++;
    }
    else {
      my $item = {
        '{#DC}'         => $dc,
        '{#NODE}'       => $node->{Node},
        '{#SERVICE_ID}' => $service->{ID},
      };

      push @services, $item;
      push @items_data,
          "- ${item_key}_service_status[$dc,$node->{Node},$service->{ID}] 1\n";
    }

    _checks( $dc, $node, $service, $count );
  }

  return;
}

sub _checks {
  my ( $dc, $node, $service, $count ) = @_;

  state %cache;

  my $url = "/v1/health/service/$service->{Service}?dc=$dc";

  unless ( $cache{$url} ) {
    $cache{$url} = _query($url);
  }

  my $data = $cache{$url};
  return unless $data;

  foreach my $check_item (@$data) {
    next unless $check_item->{Node}{Node} eq $node->{Node};

    foreach my $check ( @{ $check_item->{Checks} } ) {
      my $item = {
        '{#DC}'         => $dc,
        '{#NODE}'       => $node->{Node},
        '{#SERVICE_ID}' => $service->{ID},
        '{#CHECK_ID}'   => $check->{CheckID},
        '{#CHECK_NAME}' => $check->{Name},
      };

      my $st = $CHECK_MAP{ $check->{Status} };

      if ($count) {
        my $key = "$service->{ID},$check->{CheckID}";
        next if $check_exists{$key};

        push @checks_flow, $item;
        push @items_data, "- ${item_key}_check_status_flow[$key] $st\n";
      }
      else {
        my $key = "$dc,$node->{Node},$service->{ID},$check->{CheckID}";
        next if $check_exists{$key};

        push @checks, $item;
        push @items_data, "- ${item_key}_check_status[$key] $st\n";
      }

      $check_exists{$key} = 1;
    }
  }

  return;
}

sub _service_prettify {
  my ( $name, $tags ) = @_;

  ## Cut nomad GUIDs from service name
  ## they are changes after service restart
  $name =~ s/-[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}//g;

  ## remove tags from name (nomad add them)
  foreach my $tag (@$tags) {
    $name =~ s/\-{0,1}$tag\-{0,1}//g;
  }

  ## remove nomad stuff
  $name =~ s/\_nomad-executor\-//;

  return $name;
}

sub _detect_count {
  my $tags = shift;

  foreach my $tag (@$tags) {
    next unless index( $tag, 'count-' ) == 0;
    return substr( $tag, 6, length($tag) - 6 );
  }

  return;
}

sub _is_ignore {
  my $tags = shift;

  foreach my $tag (@$tags) {
    return 1 if $tag eq 'ignore-service';
  }

  return;
}
