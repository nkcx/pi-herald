#!/usr/bin/env perl

## PiHERALD SERVER SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-server-config.pl
#
# This script is used to convert between the PiHerald client database 
# and the client INI file.
#
# This script is intended to be used indirectly through piherald-server.pl.
#
#	piherald-server-config.pl create <tv> <file> - creates the ini <file> for TV <tv>
#	piherald-server-config.pl delete <tv> - deletes <tv> from database
#

use strict;
use warnings;
use English;
use Try::Tiny;
use Config::IniFiles;
use Storable qw(store retrieve);
use Switch;

use lib '/opt/piherald-server/lib';
use PiHeraldServer::Core;

use Data::Dumper;

my ($action, $tv, $file) = @ARGV;
my $piherald_output_dir = "/tmp";

my $clientfile = "/opt/piherald-server/piherald-server-clients";
my $outputfile="$piherald_output_dir/$tv-config.ini";

my $piheralddir = '/opt/piherald-server';
my $configfile="$piheralddir/piherald-server.ini";

my $cfg;
my $clientdb;
my $screendb;

########## SUBROUTINES ###########

sub create {
	#Creates a config file for tv $tv at $outputfile, using the data in $clienthashref, $screenhashref, and $serverhashref
	my ($tv, $clienthashref, $screenhashref, $serverhashref, $outputfile) = @_;
	
	#Now we need to build the config file for the TV
	#	The config file is in three pieces:
	#		- The client config in clientdb
	#		- The server config in the server config ini
	#		- The attached screen(s) from the screendb
	
	my %outputhash;
	
	#client db
	unless ( exists($clienthashref->{"$tv"}) ) {
		die "'$tv' not in config.\n";
	}	
	
	$outputhash{'piheraldclient'}=$clienthashref->{"$tv"};
	
	#Screen
	foreach my $screen (sort keys %$screenhashref) {
		my $i=0;
		print "Screen: $screen\nTV: $tv\n";
		if ($tv ~~ @{$screenhashref->{$screen}->{'tvs'}}) {
			$outputhash{"server$i"}{'hostname'}=$screenhashref->{$screen}->{'hostname'};
			$outputhash{"server$i"}{'display'}=$screenhashref->{$screen}->{'displaynum'};
			$outputhash{"server$i"}{'passwdfile'}='/opt/piherald/vncpasswd';
			$i++;
		}
	}
	
	#server
	my %server;	
	$server{'hostname'}=$serverhashref->{'piheraldserver'}->{'hostname'};
	$server{'domain'}=$serverhashref->{'piheraldserver'}->{'domain'};
	$server{'port'}=$serverhashref->{'piheraldserver'}->{'port'};
	$outputhash{'piheraldserver'}=\%server;
	
	print Dumper(\%outputhash);
	
	tie my %tiedhash, 'Config::IniFiles';
	%tiedhash = %outputhash;
	tied( %tiedhash )->WriteConfig( "$outputfile" ) || die "Could not write settings to file $outputfile.";
	
	return $outputfile;	
}

sub delete_tv {
	my ($tv, $clienthashref,$serverhashref) = @_;
	unless (exists $clienthashref->{$tv}) {
		print "'$tv' not in config.\n";
		usage();
	}
	
	my $clientfile = $serverhashref->{'piheraldserver'}->{'clientdb'};
	
	delete $clienthashref->{$tv};

	store($clienthashref, "$clientfile");
}

sub usage{
	die "Usage: $0 {create|delete <tv> [<file>]}\n";
}

######### MAIN ########

if (not defined $action or not defined $tv) {
	usage();
}

my ($serverhashref, $clienthashref, $screenhashref) = configparse($configfile);

switch ($action) {
	case "create"	{ create($tv,$clienthashref,$screenhashref,$serverhashref,$file) }
	case "delete"	{ delete_tv($tv,$clienthashref,$serverhashref) }
	else			{ usage() }
}