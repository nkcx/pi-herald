#!/usr/bin/env perl

## PiHERALD SERVER SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## PiHeraldServer::Core
#
# This is the core perl module for the PiHerald Server software suite.
#
# This module is intended to be used by the Perl modules, and indirectly
# by the main piherald-server.pl script.
#

use strict;
use warnings;
use English;
use Config::IniFiles;
use IO::Socket::SSL;
use Storable qw(store retrieve);
use Net::SSH::Perl;
use Crypt::CBC;


############### PID and PROCESS RELATED ###############

sub create_pid_file {
	#Writes the PID file
	my ($filename) = @_;
	open (my $fh, '>', $filename) or die "Could not open PID File $filename for writing: $!\n";
	print $fh "$$\n";
	close $fh;
}

############### CONFIG RELATED ###############

sub configparse {
	#Takes as input the PiHerald Server configfile, and outputs three hashrefs:
	#	- server config
	#	- client config
	#	- screen config
	my ($configfile) = @_;
	
	my $cfg = Config::IniFiles->new( -file => "$configfile" );
	my $piheralddir = $cfg->val('piheraldserver','dir');
	my $clientdb = $piheralddir . "/" . $cfg->val('piheraldserver','clientdb');
	my $screendb = $piheralddir . "/" . $cfg->val('piheraldserver','screendb');
	
	tie my %serverhash, 'Config::IniFiles', ( -file => "$configfile" );
	my %clienthash = %{retrieve("$clientdb")};
	my %screenhash = %{retrieve("$screendb")};
	
	return \%serverhash, \%clienthash, \%screenhash;
}

sub write_configs{
	my ($serverhash, $clienthash, $screenhash) = @_;
	my $piheralddir = $serverhash->{'piheraldserver'}->{'dir'};
	my $clientdb = $serverhash->{'piheraldserver'}->{'clientdb'};
	my $screendb = $serverhash->{'piheraldserver'}->{'screendb'};
	my $serverini = $piheralddir."/piherald-server.ini";
	
	#Write Server ini
	tie my %tiedhash, 'Config::IniFiles';
	%tiedhash = %$serverhash;
	tied( %tiedhash )->WriteConfig( "$serverini" ) || die "Could not write settings to server file.";
	
	#Write client db
	store($screenhash, "$screendb");
	
	#Write screen db
	store($clienthash, "$clientdb");
}

sub to_nested_hash {
    #Provide hashref as first variable, keys as next variables, and value as last variable.
	#Updates provided hashref at key provided location with value.
	my $ref   = \shift;  
    my $h     = $$ref;
    my $value = pop;
    $ref      = \$$ref->{ $_ } foreach @_;
    $$ref     = $value;
    return $h;
}

############### TV RELATED ###############

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

sub writetv {
	#sends config file to TV
	my ($tv,$clienthash,$serverhash,$file) = @_;

	print "$tv\n";
	
	unless (exists $clienthash->{$tv}) {
		print "ERROR: $tv is not in the client config file.\n";
		exit 3;
	}
	
	my $remotefile = '/opt/piherald/piherald-client.ini';
	
	my $host = $clienthash->{$tv}->{'ip'};
	
	my $ident = $serverhash->{'piheraldserver'}->{'sshidentfile'};
	my $user = $serverhash->{'piheraldserver'}->{'user'};
	
	my $stdout = `scp -o StrictHostKeyChecking=no $file $user\@$host:$remotefile`;
	print "$stdout\n";
}

sub tv_command {
	my ($tv,$command,$clienthash,$serverhash) = @_;
	
	unless (exists $clienthash->{$tv}) {
		print "ERROR: $tv is not in the client config file.\n";
		exit 3;
	}
	
	my $host = $clienthash->{$tv}->{'ip'};
	
	my $ident = $serverhash->{'piheraldserver'}->{'sshidentfile'};
	my $user = $serverhash->{'piheraldserver'}->{'user'};
	
	my @KEYFILE = ("$ident");
	my $ssh = Net::SSH::Perl->new($host, "strict_host_key_checking" => 'no', identity_files=>\@KEYFILE);
	
	my $cmd = "piherald-client $command";

    $ssh->login($user);
    my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
	print "$stdout\n";
}

sub vncpasswd {
	#Creates VNC password in perl
	my ($pass, $file) = @_;
	
	my $encryptedpass = `printf "$pass\n$pass\n" | vncpasswd -f`;
	
	#print "$encryptedpass\n";
	
	open(my $fh, ">", "$file") or die "Can't open $file: $!\n";
	print $fh $encryptedpass;
	close $fh;
}

1;