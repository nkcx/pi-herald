#!/usr/bin/env perl

## PiHERALD SERVER SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-server-comm.pl
#
# This script is used to receive communication from PiHerald clients, and act
# on the received information.
#
# The message the script receives is:
#		<uuid from config>,<current IP>,<hostname from config>,<cur. resx>,<cur. resy>
#
# This script is intended to be used indirectly through piherald-client.sh.
#
#	piherald-server-comm.pl - start the communication server
#

use strict;
use warnings;
use English;
use Config::IniFiles;
use IO::Socket::SSL;
use Storable qw(store retrieve);
use Net::SSH::Perl;
use sigtrap 'handler', \&process_handler, 'normal-signals';

use Data::Dumper;

my $pid_file="/home/piherald-admin/piherald-server-comm.pid";
my $piheralddir="/opt/piherald-server";
my $configfile = "$piheralddir/piherald-server.ini";

#Initialize variables
my $cfg;
my $port;
my $piheralduser;
my $socketcert;
my $socketkey;
my $clientdb;
my $screendb;
my $identfile;
my $socket;

############### SUB ROUTINES ################

sub process_handler {
	#print "$$ - Handler has triggered!\n";
	$socket->close();
	unlink $pid_file;
	exit 0;
}

sub create_pid_file {
	#Writes the PID file
	my ($filename) = @_;
	open (my $fh, '>', $filename) or die "Could not open PID File $filename for writing: $!\n";
	print $fh "$$\n";
	close $fh;
}

sub gettv {
	# Connects to the TV and gets the INI
    my ($host, $user, $ident) = @_;
	
	my @KEYFILE = ("$ident");
	my $ssh = Net::SSH::Perl->new($host, "strict_host_key_checking" => 'no', identity_files=>\@KEYFILE);
	
	my $cmd = 'cat /opt/piherald/piherald-client.ini';

    $ssh->login($user);
    my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
	
	tie my %tiedhash, 'Config::IniFiles', ( -file => \$stdout );
	
	return %tiedhash;
}

sub importtv {
	# Imports provided hash ref for tv into clientdb file
	my ($hashref, $tv, $clientdb) = @_;
	
	my %clienthash;
	if ( -f $clientdb ) {
		%clienthash = %{retrieve($clientdb)};
	}
	
	# Get only the client part of the config hash
	$hashref = %$hashref{'piheraldclient'};
	
	# Now we need to check existing record.
	#	First:  does the tv exist?  If no, create record.
	#	Second: if tv exists, and UUID matches, update record.
	#	Third:	if tv exists, and UUID does not match, increment tv and check
	#			new tv.
	#	Forth:  if incremented tv does not exist, import record there.
	
	if ( not exists $clienthash{$tv} ) {
		#We haven't seen this TV before, so we import as is
		$clienthash{$tv} = $hashref;
	} elsif ( %$hashref{'uuid'} eq $clienthash{$tv}{'uuid'} ) {
		#We have seen this exact TV before, so we import as is
		$clienthash{$tv} = $hashref;
	} else {
		#We have seen a TV with the same name, but it's not the same TV (different UUID)
		#Now we increment and check again
		my $i=1;
		while(1) {
			my $tvincr = $tv."_".$i;
			if ( not exists $clienthash{$tvincr} ) {
				#We haven't seen this TV before, so we import as is
				$clienthash{$tvincr} = $hashref;
				last;
			} elsif ( %$hashref{'uuid'} eq $clienthash{$tvincr}{'uuid'} ) {
				#We have seen this exact TV before, so we import as is
				$clienthash{$tvincr} = $hashref;
				last;
			}
			$i++;
		}
	}
	
	#print Dumper(\%clienthash);
	store(\%clienthash, "$clientdb");
}

############# MAIN ##############

#First, we check if the process is already running
if (-e $pid_file) {
	#get PID and see if process exists
	open (my $fh, $pid_file);
	chomp(my $pid = <$fh>);
	close $fh;
	
	#If running has stuff in it, we know the process is running
	my @running=`pgrep -g $pid`;
	
	if (@running) {
		print "ERROR:  Process is already running.\n";
		exit 3;
	}
}

create_pid_file($pid_file);

#Get config values
$cfg = Config::IniFiles->new( -file => "$configfile" );

$port = $cfg->val('piheraldserver','port');

$piheralduser = $cfg->val('piheraldserver','user');

$socketcert = $piheralddir . "/" . $cfg->val('piheraldserver','socketcert');
$socketkey = $piheralddir . "/" . $cfg->val('piheraldserver','socketkey');

$clientdb = $piheralddir . "/" . $cfg->val('piheraldserver','clientdb');
$screendb = $piheralddir . "/" . $cfg->val('piheraldserver','screendb');

$identfile = $cfg->val('piheraldserver','sshidentfile');

# auto-flush on socket
$| = 1;

# create socket
$socket = IO::Socket::SSL->new(
	LocalAddr => "0.0.0.0:$port",
	Listen => 5,
	SSL_cert_file => "$socketcert",
	SSL_key_file => "$socketkey",
	Reuse => 1,
	Proto => 'tcp'
) or die "ERROR in Socket Creation : $!\n";

while(1) {
	# waiting for new client connection.
	
	my $client_socket = $socket->accept();

	if (not defined $client_socket) {
		next;
	}

	# read operation on the newly accepted client
	my $data = <$client_socket>;
	
	#print "Received from Client : $data\n";
	my ($uuid,$IP,$hostname,$resx,$resy) = split(/,/,$data);

	#print "GUID:     $GUID\n";
	#print "IP Addr:  $IP\n";
	#print "Hostname: $hostname\n";
	#print "Res X:    $resx\n";
	#print "Res Y:    $resy\n";
	
	my %hash = gettv($IP, $piheralduser, $identfile);
	importtv(\%hash,$hostname,$clientdb);
}

$socket->close();
