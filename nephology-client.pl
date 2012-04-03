#!/usr/bin/perl

use strict;
use LWP;
use Getopt::Long;
use JSON;
use Try::Tiny;
use Data::Dumper;

my $version = 1;
my $neph_server = undef;
my $mac_addr = undef;
my $work_to_do = 1;
my $nephology_commands = undef;

# Get command line options
GetOptions(
    'server|s=s' => \$neph_server,
    'mac|m=s' => \$mac_addr,
    );

if (!defined($neph_server)) {
    print "Server required\n";
    exit 1;
}

print "Nephology Client version $version Startup\n\n";

my $browser = LWP::UserAgent->new;
$browser->agent('NephologyCient/' . $version . '(libwww-perl-' . $LWP::VERSION . ')');

while ($work_to_do == 1) {
    $nephology_commands = {};
    print "Getting worklist from $neph_server for $mac_addr\n";
    # Grab the worklist from the Nepology Server
    my $response = $browser->get(
	"http://" . $neph_server . "/nephology/install/" . $mac_addr,
	'X-Nephology-Client-Version' => $version,
	);

    if(! $response->is_success) {
        print("No successful response, waiting for 5min before trying again\n");
        sleep 300;
        next;
    }

    print("Got a response, processing...\n");
    try {
        $nephology_commands = JSON->new->utf8->decode($response->decoded_content);
    } catch {
        print("Resonse wasn't valid JSON, waiting for 5min before trying again\n");
        sleep 300;
        next;
    };
    #print(Dumper($nephology_commands));

    if ( $nephology_commands->{'version_required'} > $version ) {
        print("This client is out of date for the Nephology server\n");
        print("Rebooting to fetch a fresh client.\n");
        unlink("incomplete");
        while (1) { sleep(10) };
        exit 0;
    }

    foreach my $reqhash (@{$nephology_commands->{'runlist'}}) {
        print("Got command: " . JSON->new->utf8->encode($reqhash) . "\n");
    }

    print("End of run. Waiting 10 seconds before continuing.\n");
    sleep(10);
}

exit 0;
