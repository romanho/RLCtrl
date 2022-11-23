# $Id: $
#
# RWindow: kind of watchdog for window opening times
#
# In difference to standard 'watchdog' device, the time until command (alarm)
# execution is dynamic and can depend on weather conditions.
#

package main;

use strict;
use warnings;

use POSIX;

my %RWindow_attrs = (
	factor		=> { type=>"f", dflt=> 1.0 },
	openEvent	=> { type=>"s", dflt=> "open" },
	closeEvent	=> { type=>"s", dflt=> "closed" },
);

sub RWindow_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}    = "RWindow_Define";
	$hash->{UndefFn}  = "RWindow_Undefine";
	$hash->{SetFn}    = "RWindow_Set";
	$hash->{AttrFn}   = "RWindow_Attr";
	$hash->{AttrList} =
		join(" ", keys %RWindow_attrs)." ".$readingFnAttributes;
}

sub RWindow_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);

	return "Usage: define <name> RWindow <sensordev> <alarm_ev> [<weatherdev>]"  if @args < 4;
	my ($name, $type, $sdev, $wdev) = @args;
	$hash->{SENSORDEV} = $sdev;
	$hash->{ALARMEVENT} = $alev;
	$hash->{WEATHERDEV} = $wdev;
	RWindow_init($hash);
	return undef;
}

sub RWindow_Undefine($$)
{
	my ($hash,$arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub RWindow_Set($@)
{
	my ($hash, $name, $cmd, @args) = @_;

	if ($cmd eq "prolong") {
		#RWindow_start($hash);
		return undef;
	}
	# usage for GUI:
	return "Unknown argument $cmd, choose one of prolong";
}

sub RWindow_Attr($@)
{
	my ($cmd, $dev, $name, $val) = @_;

	# only check "set", not "del"
	return undef if $cmd ne "set";

	if (exists($RWindow_attrs{$name}) && (my $t = $RWindow_attrs{$name}->{type})) {
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

sub RWindow_init($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE} = 'initialized';
	RWindow_off($hash);
}

sub RWindow_opened($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

}

sub RWindow_closed($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	RemoveInternalTimer($hash, "RWindow_switch");
}

sub RWindow_set_maxtime($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{MAXTIME} = 30;
	RemoveInternalTimer($hash, "RWindow_start");
	InternalTimer($next, "RWindow_start", $hash);
}
	
sub RCattr($$)
{
	my ($name, $aname) = @_;

	$name = $name->{NAME} if ref($name) eq "HASH";
	return AttrVal($name, $aname, $RWindow_attrs{$aname}->{dflt} || "");
}
