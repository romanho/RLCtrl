# $Id: $

package main;

use strict;
use warnings;

use POSIX;
use Color;

my %RColor_attrs = (
	keeptime		=> { type=>"u", dflt=> 300 },
	transitiontime	=> { type=>"u", dflt=> 10 },
);

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
	$hash->{LIGHT1} = $ldev1;
	$hash->{LIGHT2} = $ldev2;
	RColor_init($hash);
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
		RColor_start($hash);
		return undef;
	}
	elsif ($cmd eq "off") {
		RColor_stop($hash);
		return undef;
	}	
	elsif ($cmd eq "reset") {
		RColor_init($hash);
		return undef;
	}
	# usage for GUI:
	return "Unknown argument $cmd, choose one of on off reset";
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

sub RColor_init($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE} = 'initialized';
	RColor_off($hash);

	my $ss_off = RCattr($name, "sunset_offset");
	my @t = localtime(time);
	my $t = sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0]);
	if ($t lt sunset_abs($ss_off)) {
		RColor_set_sunset_timer($hash);
	}
	else {
		RColor_start($hash);
	}
}

sub RColor_start($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	return if $hash->{PHASE} ne "off";
	
	my $dow = (localtime(time))[6];
	my $h = $dow/7/2;
	$hash->{COL1} = $h;
	$hash->{COL2} = $h + 0.5;
	$hash->{PHASE} = 0;
Log3($name, 5, "RCo($name): turned on");
	RColor_switch($hash);
}

sub RColor_stop($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	RemoveInternalTimer($hash, "RColor_switch");
	return if $hash->{PHASE} eq "off";

	RColor_off($hash);
	RColor_set_sunset_timer($hash);
}

sub RColor_off($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{PHASE} = "off";
	fhem("set $hash->{LIGHT1} off");
	fhem("set $hash->{LIGHT2} off");
	Log3($name, 3, "RCo($name): turned off");
}

sub RColor_set_sunset_timer($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $ss_off = RCattr($name, "sunset_offset");
	my $next = gettimeofday() + hms2h(sunset_rel($ss_off))*3600;

	RemoveInternalTimer($hash, "RColor_start");
	InternalTimer($next, "RColor_start", $hash);
	$hash->{STATE} = "off (next: ".FmtDateTime($next).")";
	Log3($name, 4, "RCo($name): set on timer for ".FmtDateTime($next));
}
	
sub RColor_switch($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ttime = RCattr($name, "transitiontime");
	my $ktime = RCattr($name, "keeptime");
	my $ph = $hash->{PHASE};
	$hash->{PHASE} = ($hash->{PHASE}+1) % 2;
	my $l1 = $ph+1;
	my $l2 = $ph+2; $l2 = 1 if $l2 > 2;
	my $dev1 = $hash->{"LIGHT$l1"};
	my $dev2 = $hash->{"LIGHT$l2"};
	# XXX: set v depending on light level?
	my $col1 = Color::hsv2hex($hash->{COL1}, 1.0, 0.3);
	my $col2 = Color::hsv2hex($hash->{COL2}, 1.0, 0.3);
	
	$hash->{STATE} = "alternating ($ph)";
	fhem("set $dev1 rgb $col1 $ttime");
	fhem("set $dev2 rgb $col2 $ttime");
	RemoveInternalTimer($hash, "RColor_switch");
	InternalTimer(gettimeofday() + $ktime, "RLColor_switch", $hash);
Log3($name, 5, "RCo($name): switched, next ".FmtDateTime(gettimeofday() + $ktime));
}

sub RCattr($$)
{
	my ($name, $aname) = @_;

	$name = $name->{NAME} if ref($name) eq "HASH";
	return AttrVal($name, $aname, $RColor_attrs{$aname}->{dflt} || "");
}
