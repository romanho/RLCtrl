# $Id: $
#
# RColor: special hack that sets up two RGB lights in complementary color
# The two lights swap their colors regularily.
# They start at 'sunset_offset' after sunset each day (or before, if
# negative), and are on until midnight_offset after midnight (or before,
# again)
#

package main;

use strict;
use warnings;

use POSIX;
use Color;

my %RColor_attrs = (
	keeptime		=> { type=>"u", dflt=> 300 },
	transitiontime	=> { type=>"u", dflt=> 10 },
	max_bri			=> { type=>"b", dflt=> 255 },
	sunset_offset   => { type=>"i", dflt=> -30*60 },
	midnight_offset => { type=>"i", dflt=> -10*60 },
);

my $RColor_sunset_offset = -30*60;

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
	my ($name, $type, $ldev0, $ldev1) = @args;
	$hash->{LIGHT0} = $ldev0;
	$hash->{LIGHT1} = $ldev1;
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
		elsif ($t eq "b") {
			return "Is not a valid number between 0 and 255: $val"
				if $val !~ /^\d+$/ ||
				   $val < 0 || $val > 255;
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
	my $hue = (3.0*$dow/7 * 65536) % 32768;
	$hue /= 65536;
	my $mn_off = RCattr($name, "midnight_offset");
	my $max_bri = RCattr($name, "max_bri");

	$hash->{COL1} = $hue ;
	$hash->{COL2} = $hue + 0.5;
	$hash->{PHASE} = 0;

	my @t = localtime(time);
	my $minutes_on = (24-$t[2])*3600 + (60-$t[1])*60 + (60-$t[0]) + $mn_off;
	$hash->{BRIFACTOR} = $max_bri / $minutes_on;
	$hash->{STARTTIME} = time;
	
	Log3($name, 4, sprintf "RCo($name): turned on, hues: %d %d",
		 int($hash->{COL1}*65536), int($hash->{COL2}*65536));
	
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
	fhem("set $hash->{LIGHT0} off");
	fhem("set $hash->{LIGHT1} off");
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

	my $ph = $hash->{PHASE};
	my $np = ($ph+1) % 2;
	$hash->{PHASE} = $np;
	my $max_bri = RCattr($name, "max_bri");
	my $bri = $max_bri - int((time - $hash->{STARTTIME})*$hash->{BRIFACTOR});
	return RColor_stop($hash) if ($bri < 1);

	my $hue1 = int($hash->{COL1} * 256);
	my $hue2 = int($hash->{COL2} * 256);
	Log3($name, 4, "RCo($name): ph=$ph bri=$bri");

	my $ttime = RCattr($name, "transitiontime") * 10;
	my $ktime = RCattr($name, "keeptime");
	my $cmd1 = sprintf "set %s hsv %02x%02x%02x $ttime",
		$hash->{"LIGHT$ph"}, $hue1,255,$bri;
	my $cmd2 = sprintf "set %s hsv %02x%02x%02x $ttime",
		$hash->{"LIGHT$np"}, $hue2,255,$bri;

	$hash->{STATE} = "alternating ($ph)";
	fhem($cmd1);
	fhem($cmd2);
	Log3($name, 5, "RCo($name): $cmd1");
	Log3($name, 5, "RCo($name): $cmd2");

	RemoveInternalTimer($hash, "RColor_switch");
	InternalTimer(gettimeofday() + $ktime, "RColor_switch", $hash);
	Log3($name, 4, "RCo($name): switched, next ".FmtDateTime(gettimeofday() + $ktime));
}

sub RCattr($$)
{
	my ($name, $aname) = @_;

	$name = $name->{NAME} if ref($name) eq "HASH";
	return AttrVal($name, $aname, $RColor_attrs{$aname}->{dflt} || "");
}
