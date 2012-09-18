#!/usr/bin/perl

use strict;
use LWP;
use LWP::Simple;
use Getopt::Long;
use JSON;
use Try::Tiny;

my $version = 2;
my $work_to_do = 1;
my ($neph_server, $mac_addr) = undef;

# Get command line options
GetOptions(
    'server|s=s' => \$neph_server,
    'mac|m=s' => \$mac_addr,
);

print "Nephology Client version $version Startup\n\n";

my $Browser = LWP::UserAgent->new;
$Browser->agent('NephologyCient/' . $version . '(libwww-perl-' . $LWP::VERSION . ')');

while ($work_to_do == 1) {
    my $nephology_commands = {};
    print "Getting worklist from $neph_server for $mac_addr\n";
    # Grab the worklist from the Nepology Server
    my $Response = $Browser->get(
        "http://" . $neph_server . "/install/" . $mac_addr,
        'X-Nephology-Client-Version' => $version,
	);

    unless ($Response->is_success) {
        print "No successful response, waiting for 5min before trying again\n";
        sleep 300;
        next;
    }

    print "Got a response, processing...\n";
    try {
        $nephology_commands = JSON->new->utf8->decode($Response->decoded_content);
    } catch {
        print "Resonse wasn't valid JSON, waiting for 5min before trying again\n";
        sleep 300;
        next;
    };

    if ($nephology_commands->{'version_required'} > $version) {
        print "This client is out of date for the Nephology server\n";
        print "Rebooting to fetch a fresh client.\n";
        unlink("incomplete");
        while (1) { sleep 10 };
        exit;
    }

    for my $reqhash (@{$nephology_commands->{'runlist'}}) {
        print "Got command: " . $reqhash->{'description'} . "\n";
	
	my $filename = "/tmp/deploy-" . $reqhash->{'id'};
	my $url = "http://$neph_server/install/$mac_addr/" . $reqhash->{'id'};

	if(-e $filename) {
		system("rm $filename");
	} 
	
	open(FILE, "+>", $filename);
	chmod 0755, $filename;
	my $output = get ($url);
	print FILE $output;

	system("bash $filename");
    }

    print "End of run. Waiting for 10 seconds before continuing.\n";
    sleep 10;
}

sub _check_dmidecode {
	my $ohai = `ohai`;
	my $json = JSON->new->utf8;

	my $href = $json->decode($ohai);

	my $result = $href->{'dmi'}->{'system'}->{'product_name'};
	chomp($result);
	return $result;
}

exit;
