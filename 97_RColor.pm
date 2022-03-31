# $Id: $

package main;

use strict;
use warnings;

use POSIX;
use Color;

my %RColor_attrs = (
	keeptime		=> { type=>"u", dflt=> 300 },
	transitiontime	=> { type=>"u", dflt=> 10 },
};

sub RColor_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}    = "RColor_Define";
	$hash->{UndefFn}  = "RColor_Undefine";
	$hash->{SetFn}    = "RColor_Set";
	$hash->{AttrFn}   = "RColor_Attr";
	$hash->{AttrList} =
		join(" ", keys %RColor_attrs)." ".$readingFnAttributes;
}

sub RColor_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);

	return "Usage: define <name> RColor <light1> <light2>"  if(@args < 4);
	my ($name, $type, $ldev1, $ldev2) = @args;

	$hash->{STATE} = 'initialized';
	$hash->{LIGHT1} = $ldev1;
	$hash->{LIGHT2} = $ldev2;

#	InternalTimer(gettimeofday() + RLCattr($name, "keeptime"),
#				  "RLCintervalCheck", $hash);
	return undef;
}

sub RColor_Undefine($$)
{
	my ($hash,$arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub RColor_Set($@)
{
	my ($hash, $name, $cmd, @args) = @_;

	if ($cmd eq "on") {
		RColor_start();
	}
	elsif ($cmd eq "off") {
		RColor_stop();
	}	
	# usage for GUI:
	return "Unknown argument $cmd, choose one of on off";
}

sub RColor_Attr($@)
{
	my ($cmd, $dev, $name, $val) = @_;

	# only check "set", not "del"
	return undef if $cmd ne "set";

	if (exists($RColor_attrs{$name}) && (my $t = $RColor_attrs{$name}->{type})) {
		if ($t eq "u") {
			return "Is not a valid unsigned integer number: $val"
				if $val !~ /^\d+$/;
		}
		elsif ($t eq "i") {
			return "Is not a valid integer number: $val"
				if $val !~ /^-?\d+$/;
		}
		elsif ($t eq "f") {
			return "Is not a valid real number: $val"
				if $val !~ /^-?\d*(\.\d*)?$/;
		}
		elsif ($t eq "%") {
			return "Is not a valid number between 0 and 100: $val"
				if $val !~ /^\d+$/ ||
				   $val < 0 || $val > 100;
		}
	}
	return undef;
}



sub RColor_start($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $dow = (localtime(time))[6];
	my $h = $dow * 32768/7;
	$hash->{HUE1} = $h;
	$hash->{HUE2} = $h + 32768;
	$hash->{PHASE} = 0;
	RColor_switch($hash);
}

sub RColor_stop($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	RemoveInternalTimer($hash, "RColor_switch");

	my $next = sunset(-600);
	RemoveInternalTimer($hash, "RColor_on");
	InternalTimer($next, "RLColor_on", $hash);
	$hash->{STATE} = "off (next: ".FmtDateTime($next).")";
}

sub RColor_switch($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ttime = RLCattr($name, "transitiontime");
	my $ktime = RLCattr($name, "keeptime");
	my $ph = $hash->{PHASE};
	$hash->{PHASE} = ($hash->{PHASE}+1) % 2;
	my $l1 = $ph+1;
	my $l2 = $ph+2; $l2 = 1 if $l2 > 2;

	$hash->{STATE} = "alternating ($ph)";
	fhem("set $hash->{LIGHT$l1} hue $hash->{HUE1} $ttime");
	fhem("set $hash->{LIGHT$l2} hue $hash->{HUE2} $ttime");
	RemoveInternalTimer($hash, "RColor_switch");
	InternalTimer(gettimeofday() + $ktime, "RLColor_switch", $hash);
}

sub RLCattr($$)
{
	my ($name, $aname) = @_;

	$name = $name->{NAME} if ref($name) eq "HASH";
	return AttrVal($name, $aname, $RColor_attrs{$aname}->{dflt} || "");
}
