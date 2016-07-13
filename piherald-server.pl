#!/usr/bin/env perl

## PiHERALD SERVER SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-server.pl
#
# This script manages the PiHerald server software.

use strict;
use warnings;
use English;

my $helpmsg = <<"EOT";
This script is intended to receive commands from the user and manipulate
the PiHerald Server software appropriately.  PiHerald server is a sort of
middleware for the entire PiHerald Software Suite.  All PiHerald Server
commands use the following format:

	piherald-server <action> <target> [<value>]

The following actions are recognized:
	help	- shows this help doc.
	start	- starts the specified target.
	stop	- stops the specified target.
	restart	- restarts the specified target.
	status	- provides the status of the specified target.
	list	- lists all sub targets for the specified target.
	new		- creates a new element in the specified target (only applies to screen).
	update	- updates the specified target (only applies to tv).
	*reboot	- reboots the specified target (only applies to tv or server).
	set		- sets the specified target to value.
	*append	- appends the specified value to target
	delete	- deletes the specified target. (only applies to second level targets)
	show	- alias for list.

*Not available in the current version, but planned.
	
The target is a list of words that specifically refers to a configuration
option.  For example, the target "tv tvhostname piheraldclient hostname"
refers to the "hostname" option, in the "piheraldclient" section of the 
"tvhostname" config, which is located in the tv database file.

IMPORTANT:

This script is meant to be run by a user (such as piherald-admin) who has sudo permissions.
EOT

use Try::Tiny;
use Config::IniFiles;
use Switch;
use Storable qw(store retrieve);
use File::Copy::Recursive qw(dircopy);
use Net::SSH::Perl;
use experimental 'smartmatch';

use lib '/opt/piherald-server/lib';
use PiHeraldServer::Core;

use Data::Dumper;

my $piheralddir="/opt/piherald-server/";
my $screenfolder="$piheralddir/screen";

my $configfile="$piheralddir/piherald-server.ini";

my ($action, $maintarget, @target) = @ARGV;

my $cfg;
my $clientdb;
my $screendb;

########## SUBROUTINES ###########

sub usage {
	print "Usage: $0 help|start|stop|restart|status|list|new|update|reboot|set|append|delete|show <target> [<value>]\n";
}

sub help {
	print $helpmsg;
}

sub start {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	# Check that we have enough data to do what needs to happen
	unless (defined $maintarget and ($maintarget eq "server" or @target)) {
		print "ERROR: you must provide at least two levels of target.\n";
		exit 3
	}
	
	if ($maintarget eq "tv") {
		if ($target[0] eq "all") {
			#If 'all', we start all the TVs
			print "All received!\n";
		} else {
			#otherwise, we only start the specified TV
			start_tv($target[0],$clienthash,$serverhash);
		}
	} elsif ($maintarget eq "screen") {
		if ($target[0] eq "all") {
			print "All received!\n";
		} else {
			start_screen($target[0],$screenhash);
		}
	} elsif ($maintarget eq "server") {
		start_server();
	} else {
		print "ERROR: you have provided an invalid target.  Run piherald-server list to see all valid targets.\n";
	}
}

sub start_tv {
	my ($tv,$clienthash,$serverhash) = @_;
	my $command='start';
	tv_command($tv,$command,$clienthash,$serverhash);
}

sub start_screen {
	my ($displayname,$screenhash) = @_;
	
	unless (exists $screenhash->{$displayname}) {
		print "ERROR: $displayname is not in screen config file.\n";
		exit 3;
	}
	
	my $displaynum = $screenhash->{$displayname}->{'displaynum'};
	my $resx = $screenhash->{$displayname}->{'resx'};
	my $resy = $screenhash->{$displayname}->{'resy'};
	my $websites = $screenhash->{$displayname}->{'websites'};
	my $passwd = $screenhash->{$displayname}->{'passwd'};
	
	my $dir = $screenhash->{'default'}->{'screendirectory'};
	
	my $resolution="${resx}x${resy}";
	my $passfile = "/tmp/vncpass-$displaynum";
			
	#Create VNC Passwd File
	vncpasswd($passwd,$passfile);
	
	#Start VNCServer
	`sudo -u piherald env -u SESSION_MANAGER -u DBUS_SESSION_BUS_ADDRESS vncserver :$displaynum -geometry $resolution -rfbauth $passfile`;
	
	#Start Chrome on the Server
	unless (-d "$dir/$displayname") {
		#Create chrome data directory if it doesn't exist
		
		my $source_dir = "$dir/default";
		my $target_dir = "$dir/$displayname";
		
		`sudo cp -R -p $source_dir $target_dir`;
	}
	
	`sudo -u piherald /bin/bash -c "export DISPLAY=:$displaynum; google-chrome @$websites --user-data-dir=$dir/$displayname &>/dev/null &"`;
}

sub start_server {
	system("perl /opt/piherald-server/piherald-server-comm.pl &>/dev/null &");
}

sub stop {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	# Check that we have enough data to do what needs to happen
	unless (defined $maintarget and ($maintarget eq "server" or @target)) {
		print "ERROR: you must provide at least two levels of target.\n";
		exit 3
	}
	
	if ($maintarget eq "tv") {
		if ($target[0] eq "all") {
			#If 'all', we start all the TVs
			print "All received!\n";
		} else {
			#otherwise, we only start the specified TV
			stop_tv($target[0],$clienthash,$serverhash);
		}
	} elsif ($maintarget eq "screen") {
		if ($target[0] eq "all") {
			print "All received!\n";
		} else {
			stop_screen($target[0],$screenhash);
		}
	} elsif ($maintarget eq "server") {
		stop_server();
	} else {
		print "ERROR: you have provided an invalid target.  Run piherald-server list to see all valid targets.\n";
	}
}

sub stop_tv {
	my ($tv,$clienthash,$serverhash) = @_;
	my $command='stop';
	tv_command($tv,$command,$clienthash,$serverhash);
}

sub stop_screen {
	my ($displayname,$screenhash) = @_;

	unless (exists $screenhash->{$displayname}) {
		print "ERROR: $displayname is not in screen config file.\n";
		exit 3;
	}
	
	my $displaynum = $screenhash->{$displayname}->{'displaynum'};
	
	`sudo -u piherald vncserver -kill :$displaynum`;
}

sub stop_server {
	my $pid_file="/home/piherald-admin/piherald-server-comm.pid";

	open (my $fh, '<', $pid_file) or die "Server not running.\n";
	my $pid = <$fh>;
	close ($fh);
	
	chomp $pid;
	
	`kill $pid`;
}

sub restart {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	stop($serverhash,$clienthash, $screenhash,$maintarget,@target);
	sleep 3;
	start($serverhash,$clienthash, $screenhash,$maintarget,@target);
}

sub status {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	# Check that we have enough data to do what needs to happen
	unless (defined $maintarget and ($maintarget eq "server" or @target)) {
		print "ERROR: you must provide at least two levels of target.\n";
		exit 3
	}
	
	if ($maintarget eq "tv") {
		if ($target[0] eq "all") {
			#If 'all', we start all the TVs
			print "All received!\n";
		} else {
			#otherwise, we only start the specified TV
			status_tv($target[0],$clienthash,$serverhash);
		}
	} elsif ($maintarget eq "screen") {
		if ($target[0] eq "all") {
			print "All received!\n";
		} else {
			status_screen($target[0],$screenhash);
		}
	} elsif ($maintarget eq "server") {
		status_server();
	} else {
		print "ERROR: you have provided an invalid target.  Run piherald-server list to see all valid targets.\n";
	}
}

sub status_tv {
	my ($tv,$clienthash,$serverhash) = @_;
	my $command='status';
	tv_command($tv,$command,$clienthash,$serverhash);
}

sub status_screen {
	my ($displayname,$screenhash) = @_;

	unless (exists $screenhash->{$displayname}) {
		print "ERROR: $displayname is not in screen config file.\n";
		exit 3;
	}
	
	my $displaynum = $screenhash->{$displayname}->{'displaynum'};
	
	`sudo -u piherald vncserver -kill :$displaynum`;
}

sub status_server {
	my $pid_file="/home/piherald-admin/piherald-server-comm.pid";

	open (my $fh, '<', $pid_file) or die "Server not running.\n";
	my $pid = <$fh>;
	close ($fh);
	
	chomp $pid;
	
	my @running = `pgrep -F $pid_file`;
	if (@running) {
		print "Server is runnning with PID $pid.\n";
		exit 0
	}
	else {
		die "Server not runnning.\n";
	}
}

sub list {
	my ($serverhash, $clienthash, $screenhash,$maintarget,@target) = @_;
	
	if (not defined $maintarget) {
		#We have no main target, so we list our top level
		print "tv\nscreen\nserver\n";
	} else {
		#We have a main target
		my %hash;
		my $indent="";
		
		#Get the proper hash
		if ($maintarget eq "tv") {
			%hash = %{$clienthash};
		} elsif ($maintarget eq "screen") {
			%hash = %{$screenhash};
		} elsif ($maintarget eq "server") {
			%hash = %{$serverhash};
		} else {
			print "ERROR: you have provided an invalid target. Run piherald-server list to see all valid targets.\n";
			exit 3;
		}
		
		print $indent.$maintarget."\n";
		$indent .= "    ";
		
		foreach my $trgt (@target) {
			#First, we check if the target is defined in the hash
			unless (defined $hash{$trgt}) {
				print "ERROR: invalid target '$trgt'.\n";
				exit 3;
			}
			
			#Second, we check the reference type
			if (ref $hash{$trgt} eq "HASH") {
				#The next target is a hash
				%hash = %{$hash{$trgt}};
				print $indent.$trgt."\n";
				$indent .= "    ";
			} 
			elsif (ref $hash{$trgt} eq "ARRAY") {
				#The next target is an array
				my $arrayref = $hash{$trgt};
				print $indent.$trgt." => [ "."@$arrayref"." ]\n";
				exit 0;
			}
			else {
				#We've reached the end of the chain
				print $indent.$trgt." => ".$hash{$trgt}."\n";
				exit 0;
			}
			
		}
		
		#Now, we print all the key/value pairs at the current target level
		foreach my $key (sort keys %hash) {
			#Check if the key's value is a hashref or a value
			if (ref $hash{$key} eq "HASH") {
				print $indent.$key." => { ... }\n";
			}
			elsif (ref $hash{$key} eq "ARRAY") {
				print $indent.$key." => [ ... ]\n";
			}
			else {
				print $indent.$key." => ".$hash{$key}."\n";
			}
		}
		
		exit 0;
	}
}

sub new {
	my ($serverhash, $clienthash, $screenhash,$maintarget,@target) = @_;
	
	#We need to collect the following information for the screen:
	#	- Displaynum
	#	- Resx
	#	- Resy
	#	- website(s)
	#	- passwd
	#	- tv(s)
	#	- hostname (the ip of the server, for now)
	
	# Check that we have enough data to do what needs to happen
	unless (defined $maintarget and $maintarget eq 'screen' and @target) {
		print "ERROR: only valid for screen.  You must provide a screen name.\n";
		exit 3
	}
	
	my $screen=$target[0];
	
	#get the currently use display nums
	my @displaynums;
	
	foreach my $disp (sort keys %$screenhash) {
		if (exists $screenhash->{$disp}->{'displaynum'}) {
			push @displaynums, $screenhash->{$disp}->{'displaynum'};
		}
	}
	
	my $i=1;
	while (1) {
		if ($i ~~ @displaynums) {
			$i++;
		}
		else {
			last;
		}
	}
	
	my $defaultdisplaynum = $i;
	
	#Displaynum
	print "Display number [$defaultdisplaynum]: ";
	chomp (my $displaynum = <STDIN>);
	if ($displaynum eq "") {
		$displaynum = $defaultdisplaynum;
	}
	
	#Resx
	my $defaultresx='1920';
	print "ResX [$defaultresx]: ";
	chomp (my $resx = <STDIN>);
	if ($resx eq "") {
		$resx = $defaultresx;
	}
	
	#Resy
	my $defaultresy='1080';
	print "ResY [$defaultresy]: ";
	chomp (my $resy = <STDIN>);
	if ($resy eq "") {
		$resy = $defaultresy;
	}
	
	#websites
	my $defaultwebsite='www.google.com';
	print "Website(s) (comma separated) [$defaultwebsite]: ";
	chomp (my $websites = <STDIN>);
	if ($websites eq "") {
		$websites = $defaultwebsite;
	}
	$websites =~ s/\s+//g;
	my @websites = split(/,/,$websites);
	
	#Passwd
	my $defaultpasswd='piherald';
	print "Password [$defaultpasswd]: ";
	chomp (my $passwd = <STDIN>);
	if ($passwd eq "") {
		$passwd = $defaultpasswd;
	}
	
	#TVs
	my $defaulttv='';
	print "TV(s) (comma separated) [$defaulttv]: ";
	chomp (my $tvs = <STDIN>);
	if ($tvs eq "") {
		$tvs = $defaulttv;
	}
	$tvs =~ s/\s+//g;
	my @tvs = split(/,/,$tvs);
	
	#Host
	my $defaulthost=$serverhash->{'piheraldserver'}->{'ip'};
	print "Host [$defaulthost]: ";
	chomp (my $host = <STDIN>);
	if ($host eq "") {
		$host = $defaulthost;
	}
	
	print "\n\n$screen:\nDisplaynum: $displaynum\nRes: ${resx}x${resy}\nWebsites: @websites\nPasswd: $passwd\nTVs: @tvs\nHost: $host\n";
	
	my %screen;
	$screen{'displaynum'}=$displaynum;
	$screen{'resx'}=$resx;
	$screen{'resy'}=$resy;
	$screen{'websites'}=\@websites;
	$screen{'passwd'}=$passwd;
	$screen{'tvs'}=\@tvs;
	$screen{'hostname'}=$host;
	
	$screenhash->{"$screen"}=\%screen;
	
	write_configs($serverhash, $clienthash, $screenhash);
}

sub update {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	# Check that we have enough data to do what needs to happen
	unless (defined $maintarget and ($maintarget eq "server" or @target)) {
		print "ERROR: you must provide at least two levels of target.\n";
		exit 3
	}
	
	if ($maintarget eq "tv") {
		if ($target[0] eq "all") {
			#If 'all', we start all the TVs
			print "All received!\n";
		} else {
			#otherwise, we only start the specified TV
			update_tv($target[0],$serverhash,$clienthash,$screenhash);
		}
	}
	else {
		print "ERROR: you have provided an invalid target.  Run piherald-server list to see all valid targets.\n";
	}
}

sub update_tv {
	my ($tv,$serverhash,$clienthash,$screenhash) = @_;
	unless (exists $clienthash->{$tv}) {
		die "ERROR: $tv does not exist in client db.\n";
	}
	
	my $command='update';
	my $file = "/tmp/$tv.ini";
	`perl /opt/piherald-server/piherald-server-config.pl create $tv $file`;
	
	my $ip = $clienthash->{$tv}->{'ip'};
	my $user = $serverhash->{'piheraldserver'}->{'user'};
	
	writetv($tv,$clienthash,$serverhash,$file);
	
	tv_command($tv,$command,$clienthash,$serverhash);
}

sub update_screen {
	my ($displayname,$screenhash) = @_;

	unless (exists $screenhash->{$displayname}) {
		print "ERROR: $displayname is not in screen config file.\n";
		exit 3;
	}
	
	my $displaynum = $screenhash->{$displayname}->{'displaynum'};
	
	`sudo -u piherald vncserver -kill :$displaynum`;
}

sub set {
	my ($serverhash, $clienthash, $screenhash,$maintarget,@target) = @_;
	
	if (not defined $maintarget) {
		#We have no main target, so we list our top level
		print "ERROR: Must provide target\n";
	} 
	elsif (scalar @target lt 2) {
		#We need at least one key and one value
		print "ERROR:  Must provide at least one key and one value.\n"
	}
	else {
		#We have a main target
		my %hash;
		
		#Get the proper hash
		if ($maintarget eq "tv") {
			%hash = %{$clienthash};
		} elsif ($maintarget eq "screen") {
			%hash = %{$screenhash};
		} elsif ($maintarget eq "server") {
			%hash = %{$serverhash};
		} else {
			print "ERROR: you have provided an invalid target. Run piherald-server list to see all valid targets.\n";
			exit 3;
		}
		
		#Check if value is an array, and modify it
		if ( $target[-1] =~ /\[.*\]/) {
			#The value is an array
			my $value = $target[-1];
			$value =~ s/^\[//;
			$value =~ s/\]$//;
			$value =~ s/\s+//g;
			my @array = split(/,/, $value);
			$target[-1] = \@array;
		}
		
		to_nested_hash(\%hash,@target);
		
		print Dumper(\%hash);
		
		write_configs($serverhash, $clienthash, $screenhash);
		
		exit 0;
	}
}

sub delete_ph {
	my ($serverhash,$clienthash, $screenhash,$maintarget,@target) = @_;
	
	#Check if we have enough data to do what we want to do
	unless (defined $maintarget and ($maintarget eq 'screen' or $maintarget eq 'tv') and @target) {
		print "ERROR: only valid for screen and tv.  You must provide a specific screen or tv to delete.\n";
		exit 3
	}
	
	my $target = $target[0];
	
	if ($maintarget eq "tv") {
		delete $clienthash->{$target};
	} elsif ($maintarget eq "screen") {
		delete $screenhash->{$target};
	} else {
		print "ERROR: you have provided an invalid target. Run piherald-server list to see all valid targets.\n";
		exit 3;
	}
	
	write_configs($serverhash, $clienthash, $screenhash);
	
}

######## MAIN PROGRAM #######
my ($serverhash, $clienthash, $screenhash) = configparse($configfile);

switch ($action) {
	case "help"		{ help() }
	case "start"	{ start($serverhash,$clienthash, $screenhash,$maintarget,@target) }
	case "stop"		{ stop($serverhash,$clienthash, $screenhash,$maintarget,@target) }
	case "restart"	{ restart($serverhash,$clienthash, $screenhash,$maintarget,@target) }
	case "status"	{ status($serverhash,$clienthash, $screenhash,$maintarget,@target) }
	case "list"		{ list($serverhash, $clienthash, $screenhash,$maintarget,@target) }
	case "new"		{ new($serverhash, $clienthash, $screenhash,$maintarget,@target) }
	case "update"	{ update($serverhash, $clienthash, $screenhash,$maintarget,@target) }
	case "reboot"	{ usage() }
	case "set"		{ set($serverhash, $clienthash, $screenhash,$maintarget,@target) }
	case "append"	{ usage() }
	case "delete"	{ delete_ph($serverhash,$clienthash, $screenhash,$maintarget,@target) }
	case "show"		{ list($serverhash, $clienthash, $screenhash,$maintarget,@target) }
	else 			{ usage() }
}
