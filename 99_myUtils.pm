package main;
use strict;
use warnings;

#
# ----------------------------------------------------------------------
# Tanken
#

# damit die Funktion richtig funktioniert müssen alle Tankstellennamen mit 
# "Tankstelle_" beginnen oder entsprechend devspec2array auf die eigenen
# Namen anpassen

sub Tanken_get($$) {
	my ($name, $kind) = @_;
	my $high = 9999;
	my $v = ReadingsNum($name, $kind, $high);
	if ($v != $high && ReadingsVal($name, "age", 0) > 2) {
		$v = $high;
	}
	return $v;
}

sub Tanken_least_price($) {
  my ($kind) = @_;
  return (sort map {Tanken_get($_,$kind)} devspec2array("Tankstelle_.*"))[0];
}

sub Tanken_least_info {
  (my $kind = $_[0]) =~ s/:$//;
  return if $kind !~ /Diesel|Super/;
  my ($minP, $minW) = (9998, "");
  foreach my $t (devspec2array("Tankstelle_.*")) {
	  my $p = Tanken_get($t, $kind);
	  (my $name = $t) =~ s/Tankstelle_//;
	  if ($p < $minP) {
		  ($minP, $minW) = ($p, $name);
	  }
	  elsif ($p == $minP) {
		  $minW .= ",$name";
	  }
  }

  (my $k = $kind) =~ s/ .*$//;
  $minP =~ s,9$,<sup>9</sup>,;
  fhem("set Tanken_min${k}_preis $minP");
  fhem("set Tanken_min${k}_tankstellen $minW");
}

#
# ----------------------------------------------------------------------
# Lueften
# 

my $wi_dev = "wi_ac_";
my $wi_movetime = 30;

sub my_air_duration() {
	my $temp = ReadingsVal("weather", "temperature", 10);
	my $wind = ReadingsVal("weather", "wind", 0);
	my $weather = ReadingsVal("weather", "weather", "");
	my $mins = 1;

	   if ($temp <=  0) { $mins =  3; }
	elsif ($temp <=  5) { $mins =  5; }
	elsif ($temp <= 10) { $mins =  8; }
	elsif ($temp <= 14) { $mins = 12; }
	elsif ($temp <= 16) { $mins = 20; }
	elsif ($temp <= 20) { $mins = 30; }
	else                { $mins = 45; }

	# longer if cold but sunny:
	$mins += 3 if $mins < 10 && $weather eq "sonnig";

	# limit time if stormy:
	if ($wind >= 55) {
		$mins = 3 if $mins >= 3;
	}
	elsif ($wind >= 35) {
		$mins /= 2 if $mins > 10;
		$mins = 8 if $mins >= 8;
	}

	return $mins;
}

sub my_do_air($) {
	my($name) = @_;
	my $open_time = my_air_duration();

	# don't open again (and close later...) if opened manually
	return if ReadingsVal("wz_wse", "state", "") eq "open";	

	fhem("setstate $name opening for $open_time minutes; ".
	     "set ${wi_dev}open on-for-timer $wi_movetime; ".
	     "sleep ".($open_time*60)."; ".
	     "setstate $name closing; ".
	     "set ${wi_dev}close on-for-timer ".($wi_movetime+3)."; ".
	     "setstate $name closed");
}

# 
# ----------------------------------------------------------------------
# Fenster
# 

sub my_window_since($)
{
	my ($name) = @_;

	if (ReadingsVal($name, "state", "") eq "open") {
		my $age = ReadingsAge($name,"state",undef);
		return "< 1 min" if ($age < 60);
		return sprintf "%d min", int($age/60);
	}
	else {
		return "-";
	}
}

sub my_window_alarm($)
{
	my($name) = @_;
	my $temp = ReadingsVal("weather", "temperature", 10);
	if ($temp >= 18) {
Log3($name, 3, "temp=$temp -> retrigger");
		fhem("trigger $name .");
	}
	else {
Log3($name, 3, "temp=$temp -> alarm");
		fhem("set wz_ac_stehlampe blink 12 1");
	}
}

#
# ----------------------------------------------------------------------
# CT toggle (3-stufig)
# 

sub ctToggle($)
{
	my($name) = @_;
	my $ct = ReadingsVal($name, "coltempk", 0);
	$ct = 1000000 / ReadingsVal($name, "ct", 0) if !$ct;
	return if !$ct;

	   if ($ct < 4000) { fhem("set $name ct 4000"); }
	elsif ($ct < 5000) { fhem("set $name ct 6400"); }
	else               { fhem("set $name ct 2450"); }
}

# ----------------------------------------------------------------------
# misc
#

sub time_alt_str2num($)
{
	my ($val) = @_;
	return 0 if $val !~ /^(\d+)\.(\d+)\.(\d+)( (\d+:\d+(:\d+)?))?$/;
	my ($d, $m, $y, $HMS) = ($1, $2, $3, $5);
	$HMS ||= "00:00:00";
	$HMS .= ":00" if !$6;
	return time_str2num("$y-$m-$d $HMS");
}

#############################################################################

sub myUtils_Initialize($$)
{
  my ($hash) = @_;
}
1;
