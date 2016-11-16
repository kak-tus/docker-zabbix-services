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

my @items_data;

my %check_exists;

_dcs();

my $val = encode_json( { data => \@dcs } );
`zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME} -k '$ENV{SRV_DISCOVERY_KEY}_dcs' -o '$val'`;
$val = encode_json( { data => \@nodes } );
`zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME} -k '$ENV{SRV_DISCOVERY_KEY}_nodes' -o '$val'`;
$val = encode_json( { data => \@services } );
`zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME} -k '$ENV{SRV_DISCOVERY_KEY}_services' -o '$val'`;
$val = encode_json( { data => \@checks } );
`zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME} -k '$ENV{SRV_DISCOVERY_KEY}_checks' -o '$val'`;

my ( $fh, $filename ) = tempfile();
binmode $fh, ':utf8';
print $fh @items_data;
close $fh;

`zabbix_sender -z $ENV{SRV_ZABBIX_SERVER} -s $ENV{SRV_HOSTNAME} -i $filename`;

sub _query {
  my $addr = shift;

  my $url  = "http://$ENV{CONSUL_HTTP_ADDR}$addr";
  my $resp = $ua->get($url);

  unless ( $resp->is_success ) {
    die 'Consul unacessible';
  }

  return decode_json( $resp->decoded_content );
}

sub _dcs {
  my $data = _query('/v1/catalog/datacenters');
  foreach my $dc (@$data) {
    push @dcs, { '{#DC}' => $dc };
    push @items_data, "- ${item_key}_dc_status[$dc] 1\n";

    _nodes($dc);
  }

  return;
}

sub _nodes {
  my $dc = shift;

  my $data = _query("/v1/catalog/nodes?dc=$dc");

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

  foreach my $service ( values %{ $data->{Services} } ) {
    $service->{ID} = _service_prettify( $service->{ID} );

    my $item = {
      '{#DC}'         => $dc,
      '{#NODE}'       => $node->{Node},
      '{#SERVICE_ID}' => $service->{ID},
    };
    push @services, $item;
    push @items_data,
        "- ${item_key}_service_status[$dc,$node->{Node},$service->{ID}] 1\n";

    _checks( $dc, $node, $service );
  }

  return;
}

sub _checks {
  my ( $dc, $node, $service ) = @_;

  my $data = _query("/v1/health/service/$service->{Service}?dc=$dc");

  foreach my $check_item (@$data) {
    next unless $check_item->{Node}{Node} eq $node->{Node};

    foreach my $check ( @{ $check_item->{Checks} } ) {
      my $key = "$dc,$node->{Node},$service->{ID},$check->{CheckID}";
      next if $check_exists{$key};
      $check_exists{$key} = 1;

      my $item = {
        '{#DC}'         => $dc,
        '{#NODE}'       => $node->{Node},
        '{#SERVICE_ID}' => $service->{ID},
        '{#CHECK_ID}'   => $check->{CheckID},
        '{#CHECK_NAME}' => $check->{Name},
      };
      push @checks, $item;

      my $st = $CHECK_MAP{ $check->{Status} };
      push @items_data,
          "- ${item_key}_check_status[$dc,$node->{Node},$service->{ID},$check->{CheckID}] $st\n";
    }
  }

  return;
}

sub _service_prettify {
  my $name = shift;
  ## Cut nomad GUIDs from service name
  ## they are changes after service restart
  $name =~ s/-[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}//g;
  return $name;
}
