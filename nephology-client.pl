#!/usr/bin/perl

use strict;
use LWP;
use Getopt::Long;
use JSON;
use Try::Tiny;
use Data::Dumper;
use File::Temp;

my $version = 3;
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
$browser->agent('NephologyCient/' . $version . ' (libwww-perl-' . $LWP::VERSION . ')');

while ($work_to_do == 1) {
    $nephology_commands = {};
    print "Getting worklist from $neph_server for $mac_addr\n";
    # Grab the worklist from the Nepology Server
    my $response = $browser->get(
	"http://" . $neph_server . "/nephology/install/" . $mac_addr,
	'X-Nephology-Client-Version' => $version,
	);

    if(! $response->is_success) {
	print("Node not found, going to create a stub. Waiting 30s for network crap.\n");
	sleep 30;
	print("Gathering OHAI data...");
	my $ohai_data = `sudo ohai`;
	print("done.\n");
	print("Sending...");
	my $ohai_response = $browser->post(
		"http://" . $neph_server . "/nephology/node/" . $mac_addr,
        	'X-Nephology-Client-Version' => $version,
		Content => [
			'ohai' => $ohai_data,
		],
	);
	if ($ohai_response->is_success) {
		print("Done!\nNode created, will try installation again in 15sec\n");
		sleep 15;
		next;
	} else {
	        print("Nope.\nNo successful response, waiting for 5min before trying again\n");
	        sleep 300;
	        next;
	} # if ohai reponse
    } # if reponse

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
        print("Got rule [$reqhash->{'id'}], going to try and process it.");
        if ($reqhash->{'type_id'} == 1) {
            my $tmp = File::Temp->new();
            my $tmp_fn = $tmp->filename;
            my $data = $browser->get(
                "http://" . $neph_server . "/nephology/install/" . $mac_addr . "/" . $reqhash->{'id'},
                'X-Nephology-Client-Version' => $version,
                );
            if (! $data->is_success) { failure("Could not get data for $reqhash->{'rule_id'}"); }
            print $tmp $data->decoded_content;
            system("bash $tmp_fn");
            my $retcode = $?;
            if ($retcode > 0) {failure("Bad exec for rule [$reqhash->{'rule_id'}]: " . $?);}
        }
        elsif ($reqhash->{'type_id'} == 4) {
            my $tmp = File::Temp->new();
            my $tmp_fn = $tmp->filename;
            my $data = $browser->get(
                "http://" . $neph_server . "/nephology/install/" . $mac_addr . "/" . $reqhash->{'id'},
                'X-Nephology-Client-Version' => $version,
                );
            if (! $data->is_success) { failure("Could not get data for $reqhash->{'rule_id'}"); }
            print $tmp $data->decoded_content;
            system("sudo bash $tmp_fn");
            my $retcode = $?;
            if ($retcode > 0) {failure("Bad exec for rule [$reqhash->{'rule_id'}]: " . $?);}
        }
        elsif ($reqhash->{'type_id'} == 2) {
            my $data = $browser->get(
                "http://" . $neph_server . "/nephology/install/" . $mac_addr . "/" . $reqhash->{'id'},
                'X-Nephology-Client-Version' => $version,
                );
            if (! $data->is_success) { failure("Reboot requested by rule [$reqhash->{'rule_id'}] but server had error!"); }
            print("*********** RESTART REQUESTED BY RULE [$reqhash->{'rule_id'}] IN PROGRESS\n");
            unlink("incomplete");
            while (1) { sleep(10) };
        }
        elsif ($reqhash->{'type_id'} == 3) {
            my $data = $browser->get(
                "http://" . $neph_server . "/nephology/install/" . $mac_addr . "/" . $reqhash->{'id'},
                'X-Nephology-Client-Version' => $version,
                );
            if (! $data->is_success) { failure("Could not get data for $reqhash->{'rule_id'}"); }
            print("Server side rule output follows:\n");
            print($data->decoded_content . "\n");
        }
        else {
            print("Got unsupported command: " . JSON->new->utf8->encode($reqhash) . "\n");
        }
    }

    print("End of run. Waiting 90 seconds before continuing.\n");
    sleep(90);
}

exit 0;

sub failure {
    my $message = shift;
    system("sudo ipmitool chassis identify force");
    print("CLIENT FAILURE: " . $message . "\n");
    while (1) { sleep(10) };
}
