# $Id: $

package main;

use strict;
use warnings;

use POSIX;
#use Color;
#use SetExtensions;

my %RLCtrl_attrs = (
	motionOnTime		=> { type=>"u", dflt=> 240 },
	maxAutoBrightness	=> { type=>"%", dflt=> 100 },
	manualTimeout		=> { type=>"u", dflt=> 6*60*60 },
	checkInterval		=> { type=>"u", dflt=> 5*60 },
	luxThreshH			=> { type=>"u", dflt=> 60 },
	luxThreshL			=> { type=>"u", dflt=> 20 },
	lightFeedback		=> { type=>"f", dflt=> 0.5 },
	dayTime				=> { type=>"s", dflt=> "" },
	nightTime			=> { type=>"s", dflt=> "" },
	nightLevel			=> { type=>"u", dflt=> 10 },
	ctTimes				=> { type=>"s", dflt=> "" },
	ctMin				=> { type=>"u", dflt=> 2400 },
	ctMax				=> { type=>"u", dflt=> 6000 },
	motionEvent			=> { type=>"s", dflt=> "state: *motion" },
	lightEvent			=> { type=>"s", dflt=> "lux:.*" },
	lightReading		=> { type=>"s", dflt=> "lux" },
);
my %RLCtrl_defattrs = (
	icon => "it_cpu",
	devStateIcon => "{RLCtrl_stateicon(\$name);;}",
	webCmd => "dim:coltemp:auto",
	widgetOverride => "dim:colorpicker,BRI,0,1,100 coltemp:colorpicker,CT,2700,100,5000",
);
	
my $RLC_def_coltemp = 3850;
my $RLC_starttime;

sub RLCtrl_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}    = "RLCtrl_Define";
	$hash->{UndefFn}  = "RLCtrl_Undefine";
	$hash->{NotifyFn} = "RLCtrl_Notify";
	$hash->{SetFn}    = "RLCtrl_Set";
	$hash->{GetFn}    = "RLCtrl_Get";
	$hash->{AttrFn}   = "RLCtrl_Attr";
	$hash->{AttrList} =
		join(" ", keys %RLCtrl_attrs)." ".$readingFnAttributes;
	$RLC_starttime = time();
}

sub RLCtrl_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);

	return "Usage: define <name> RLCtrl <lightdev,...> <motionsensor> [<lightsensor>]"  if(@args < 3);
	my ($name, $type, $ldevs, $msens, $lsens) = @args;

	$hash->{STATE} = 'Initialized';
	$hash->{LIGHTDEV} = $ldevs;
	$hash->{MOTIONSENSOR} = $msens;
	$hash->{LIGHTSENSOR} = $lsens;
	$hash->{MODE} = "auto";
	$hash->{MAN_BRI} = "0";
	$hash->{PRESENCE} = 0;

	foreach my $a (keys %RLCtrl_defattrs) {
		if (!exists($attr{$name}->{$a})) {
			$attr{$name}->{$a} = $RLCtrl_defattrs{$a};
		}
	}

	RLCtrl_setup_timers($hash) if $init_done;
	return undef;
}

sub RLCtrl_Undefine($$)
{
	my ($hash,$arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}


sub RLCtrl_Notify($$)
{
	my ($hash, $fromdev) = @_;
	my $name  = $hash->{NAME};
	my $fromname  = $fromdev->{NAME};

	if (IsDisabled($name)) {
		Log3($name, 5, "RLC($name): is disabled");
		return "";
	}

	my $events = deviceEvents($fromdev, 1);
	my $motion_event = RLCattr($name, "motionEvent");
	my $light_event = RLCattr($name, "lightEvent");
	
	RLCtrl_setup_timers($hash)
		if ($name eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @$events));
	
	if (RLCtrl_isin($fromname, devspec2array($hash->{MOTIONSENSOR}, $hash))) {
		foreach my $ev (@$events) {
			Log3($name, 5, "RLC($name): proc event $ev from $fromname");
			next if $ev !~ /$motion_event/;
			$hash->{PRESENCE} = 1;
			RLCtrl_on_for_timer($hash);
			RLCtrl_exec($hash);
		}
	}
	elsif ($fromname eq $hash->{LIGHTSENSOR}) {
		foreach my $ev (@$events) {
			Log3($name, 5, "RLC($name): proc event $ev from $fromname");
			next if $ev !~ /$light_event/;
			Log3($name, 4, "RLC($name): lightsensor event");
			RLCtrl_exec($hash);
		}
	}
}

sub RLCtrl_Set($@)
{
	my ($hash, $name, @cmd) = @_;
	while(@cmd) {
		my $msg = RLCtrl_Set_single($hash, $name, \@cmd);
		return $msg if defined($msg);
	}
	return undef;
}

sub RLCtrl_Set_single($@)
{
	my ($hash, $name, $args) = @_;
	my $new_bri;
	my $cmd = shift @$args;

	Log3($name, 5, "RLC($name): set $cmd @$args") if $cmd ne "?";
	if ($cmd eq "on") {
		return RLCtrl_manbri($hash, 100);
	}
	elsif ($cmd eq "off") {
		return RLCtrl_manbri($hash, 0);
	}
	elsif ($cmd eq "toggle") {
		# TODO: maybe store previous brightness
		my $bri = ReadingsVal($name, "pct", 0);
		return RLCtrl_manbri($hash, $bri > 0 ? 0 : 100);
	}
	elsif ($cmd eq "dimUp") {
		my $d = (@$args && $args->[0] =~ /^\d+$/) ? shift @$args : 10;
		return RLCtrl_manbri($hash, $d, 1);
	}
	elsif ($cmd eq "dimDown") {
		my $d = (@$args && $args->[0] =~ /^\d+$/) ? shift @$args : 10;
		return RLCtrl_manbri($hash, -$d, 1);
	}
	elsif ($cmd =~ /^(dim)?(\d+)/) {
		return RLCtrl_manbri($hash, $2);
	}
	elsif ($cmd eq "dim" || $cmd eq "pct") {
		return "set $name $cmd needs a numeric argument"
			if !@$args || $args->[0] !~ /^\d+$/;
		return RLCtrl_manbri($hash, shift @$args);
	}
	elsif ($cmd eq "auto") {
		RLCtrl_auto($hash);
		return undef;
	}
	elsif ($cmd eq "for") {
		return "set $name for needs a numeric argument"
			if !@$args || $args->[0] !~ /^\d+$/;
		return RLCtrl_auto_after_timer($hash, shift @$args);
	}
	elsif ($cmd eq "ct" || $cmd eq "coltemp") {
		if (@$args && $args->[0] eq "auto") {
			$hash->{MAN_CT} = undef;
		}
		elsif (@$args && $args->[0] =~ /^\d+$/) {
			$hash->{MAN_CT} = $args->[0];
		}
		else {
			return "set $name ct needs a numeric argument or \"auto\"";
		}
		shift @$args;
		RLCtrl_exec($hash);
		return undef;
	}
	elsif ($cmd eq "scene") {
		my $name = shift @$args;
		return "set $name scene needs an scene name" if !$name;
		if (@$args && $args->[0]) {
			$hash->{SCENES}{$name} = join(" ", @$args);
		}
		else {
			delete $hash->{SCENES}{$name};
		}
		return undef;
	}
	elsif (exists($hash->{SCENES}{$cmd})) {
		foreach my $str (split(";", $hash->{SCENES}{$cmd})) {
			Log3($name, 4, "RLC($name): executing scene cmd '$str'");
			if ($str =~ /^set/) {
				fhem($str);
			}
			else {
				RLCtrl_Set($hash, $name, split(/\s+/, $str));
			}
		}
		return undef;
	}
	
	# usage for GUI:
	return "Unknown argument $cmd, choose one of auto for on off toggle dimUp dimDown dim:0,10,20,30,40,50,60,70,80,90,100 coltemp:2700,3800,5000,auto scene ".join(" ", keys %{$hash->{SCENES}});
}

sub RLCtrl_manbri($$;$)
{
	my ($hash, $bri, $rel) = @_;
	my $name = $hash->{NAME};

	if ($rel) {
		my $obri = ReadingsVal($hash->{NAME}, "pct", 0);
		$bri = $obri + $bri;
	}
	
	$hash->{MODE} = "manual";
	$hash->{MODECHANGE} = time();
	$hash->{MAN_BRI} = $bri < 0 ? 0 : $bri > 100 ? 100 : $bri;
	$hash->{PRESENCE} = 0 if $bri <= 0;
	Log3($name, 3, "RLC($name): manual set bri=$bri");
	RLCtrl_exec($hash);
	RLCtrl_auto_after_timer($hash);
	return undef;
}

sub RLCtrl_auto($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{MODE} = "auto";
	$hash->{MAN_BRI} = undef;
	$hash->{MAN_CT} = undef;
	$hash->{MODECHANGE} = time();
	RemoveInternalTimer($hash, "RLCtrl_autoTimer");
	RLCtrl_exec($hash);
}

sub RLCtrl_Get($@)
{
	my ($hash, $name, $opt, @args) = @_;
	return "$name: get needs at least one arg" if !defined($opt);

	Log3($name, 5, "RLC($name): get $opt @args");
	# Readings:
	# ---------
	# status
	# brightness/pct, ct, rgb, mode:auto/manual/SCENE
	# presence, rawlux, efflux

	if ($opt eq "presence") {
		return $hash->{PRESENCE};
	}
	if ($opt eq "dim" || $opt eq "pct") {
		return ReadingsVal($name, "pct", 0);
	}
	if ($opt eq "ct" || $opt eq "coltemp") {
		return ReadingsVal($name, "ct", 0);
	}
	if ($opt eq "mode") {
		return $hash->{MODE};
	}
	return "Unknown argument $opt, choose one of mode presence dim coltemp";
}

sub RLCtrl_Attr($@)
{
	my ($cmd, $dev, $name, $val) = @_;

	# only check "set", not "del"
	return undef if $cmd ne "set";

	if (exists($RLCtrl_attrs{$name}) && (my $t = $RLCtrl_attrs{$name}->{type})) {
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
	#elsif ($name eq "twilightDevice") {
	#	return "Is not a Twilight device: $val"
	#		if !exists($defs{$val}) || $defs{$val}{TYPE} ne "Twilight";
	#}
	
	return undef;
}

# this is the main control algorithm
sub RLCtrl_exec($)
{
	my $hash = shift;
	my $name = $hash->{NAME};
	my $ct  = RLCtrl_coltemp($hash);

	if ($hash->{MODE} ne "auto") {
		my $age = time() - ($hash->{MODECHANGE} || $RLC_starttime);
		RLCtrl_doset($hash, $hash->{MAN_BRI}, $ct,
					 "manually set since ${age}s");
		return;
	}
	my $lux = RLCtrl_corrlux($hash, $hash->{LIGHTSENSOR});
	if ($hash->{PRESENCE}) {
		my $lux_thresh_h = RLCattr($name, "luxThreshH");
		my $lux_thresh_l = RLCattr($name, "luxThreshL");
		$lux_thresh_l = $lux_thresh_h/2 if $lux_thresh_l > $lux_thresh_h;
		
		my $bri = 0;
		if (RLCtrl_in_time($hash, "nightTime")) {
			$bri = RLCattr($name, "nightLevel");
		}
		elsif (RLCtrl_in_time($hash, "dayTime")) {
			$bri = 0;
		}
		elsif ($lux <= $lux_thresh_h) {
			my $mx = RLCattr($name, "maxAutoBrightness");
			if ($lux_thresh_h == $lux_thresh_l) {
				$bri = $mx;
			}
			else {
				$bri = int(($lux_thresh_h-$lux)*$mx/($lux_thresh_h-$lux_thresh_l));
				$bri = $mx if $bri > $mx;
			}
		}
		RLCtrl_doset($hash, $bri, $ct, "$lux eff.Lux, motion");
	}
	else {
	  RLCtrl_doset($hash, 0, $ct, "$lux eff.Lux, no motion");
	}
}

# ----------------------------------------------------------------------
# RLCtrl_exec helpers

# set lights and store necessary values
sub RLCtrl_doset($$$$)
{
	my ($hash, $bri, $ct, $msg) = @_;
	my $name = $hash->{NAME};
	my $ldev = $hash->{LIGHTDEV};

	fhem("set $ldev ".($bri ? ($ct ? "ct $ct : " : "")."pct $bri : on" : "off"))
		if $ldev;

	my $state = "Dim $bri, CT $ct ($msg)";
	my $pbri = ReadingsVal($name, "pct", 0);
	$hash->{STATE} = $state;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $state);
	readingsBulkUpdate($hash, "mode", $hash->{MODE});
	readingsBulkUpdate($hash, "prevpct", $pbri);
	readingsBulkUpdate($hash, "pct", $bri);
	readingsBulkUpdate($hash, "ct", $ct);
	readingsEndUpdate($hash, 1);
	Log3($name, 4, "RLC($name): doset bri=$bri ct=$ct");
}

sub RLCtrl_in_time($$)
{
	my ($hash, $attr) = @_;
	my $name = $hash->{NAME};
	my $tstr = RLCattr($name, $attr);
	return 0 if !$tstr;

	my ($sta, $end) = split(/[\s\/-]/, $tstr);
	return 0 if !RLCtrl_good_time($hash, $sta, $attr);
	return 0 if !RLCtrl_good_time($hash, $end, $attr);

	my ($curr) = RLCtrl_gettime();
	if ($sta lt $end) {
		return $sta le $curr && $curr lt $end;
	}
	else {
		# crosses 00:00 day border
		return $curr ge $sta || $curr lt $end;
	}
}

# define a color temperature based on time
sub RLCtrl_coltemp($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	return $hash->{MAN_CT} if defined($hash->{MAN_CT});
	
	my $times = RLCattr($name, "ctTimes");
	return $RLC_def_coltemp if !$times;

	my @t = split(/[\s\/-]/, $times);
	return $RLC_def_coltemp if !RLCtrl_good_time($hash, $t[0], "ctTimes");
	return $RLC_def_coltemp if !RLCtrl_good_time($hash, $t[1], "ctTimes");
	
	my ($curr, $cur) = RLCtrl_gettime();
	my $mi = RLCattr($name, "ctMin");
	my $ma = RLCattr($name, "ctMax");
	my $ra = $ma - $mi;
	
	if ($curr le $t[0]) {
		Log3($name, 4, "RLC($name): coltemp: <= t0 -> min $mi");
		return $mi;
	}
	elsif ($curr le $t[1]) {
		Log3($name, 4, "RLC($name): coltemp: > t0, <= t1 -> max $ma");
		return $ma;
	}
	elsif (@t > 1 && RLCtrl_good_time($hash, $t[2], "ctTimes") && $curr le $t[2]) {
		my ($t1h, $t1m) = split(':', $t[1]);
		my ($t2h, $t2m) = split(':', $t[2]);
		my $t1 = $t1h*60+$t1m;
		my $t2 = $t2h*60+$t2m;
		my $scale = 1 - ($cur-$t1)/($t2-$t1);
		my $interpolated = $mi + int($ra*$scale + 0.5);
		
		Log3($name, 4, sprintf "RLC(%s): coltemp: > t1, <= t2 -> interp %.3f -> %dK", $name, $scale, $interpolated);
		return $interpolated;
	}
	else {
		Log3($name, 4, "RLC($name): coltemp: > t2 => $mi");
		return $mi;
	}
}

# correct lux value from (Aqara) light sensors if lights are on (feedback!)
sub RLCtrl_corrlux($$)
{
	my ($hash, $devlux) = @_;
	my $name = $hash->{NAME};

	return 0 if !exists($defs{$devlux});
	my $rawlux = ReadingsVal($devlux,
							 RLCattr($name, "lightReading"),
							 0);
	my $factor = RLCattr($name, "lightFeedback");
	my $age = ReadingsAge($name, "prevpct", 0);
	my $bri = ReadingsVal($name, $age<10 ? "prevpct" : "pct", 0);
	my $corr = POSIX::floor($rawlux*$factor*$bri/100 + 0.5);
	my $clux = $rawlux - $corr;
	Log3($name, 4, sprintf "RLC($name): corrlux: ".
		 "raw %3d+%s bri %3d (age %3ds)->corr %2d->clux %3d",
		 $rawlux,$age < 10 ? "prev":"curr", $bri, $age, $corr, $clux);
	return $clux > 0 ? $clux : 0;
}

# ----------------------------------------------------------------------
# timer handling

sub RLCtrl_setup_timers($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash, "RLCintervalCheck");
	if (RLCattr($name, "nightTime") || RLCattr($name, "ctTimes")) {
		InternalTimer(gettimeofday() + RLCattr($name, "checkInterval"),
					  "RLCintervalCheck", $hash);
		Log3($name, 5, "RLC($name): new interval timer");
	}
}

sub RLCtrl_on_for_timer($;$)
{
	my ($hash, $duration) = @_;
	my $name = $hash->{NAME};

	$duration ||= RLCattr($name, "motionOnTime");
	RemoveInternalTimer($hash, "RLCtrl_offTimer");
	InternalTimer(gettimeofday() + $duration,
				  "RLCtrl_offTimer", $hash);
	Log3($name, 3, "RLC($name): on-for-timer $duration");
}

sub RLCintervalCheck($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	RLCtrl_exec($hash);
	InternalTimer(gettimeofday() + RLCattr($name, "checkInterval"),
				  "RLCintervalCheck", $hash);
	Log3($name, 5, "RLC($name) refreshed interval timer");
}

sub RLCtrl_offTimer($)
{
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	Log3($name, 3, "RLC($name): off by timer");
	$hash->{PRESENCE} = 0;
	RLCtrl_exec($hash);
}

sub RLCtrl_auto_after_timer($;$)
{
	my ($hash, $duration) = @_;
	my $name = $hash->{NAME};

	$duration ||= RLCattr($name, "manualTimeout");
	RemoveInternalTimer($hash, "RLCtrl_autoTimer");
	InternalTimer(gettimeofday() + $duration,
				  "RLCtrl_autoTimer", $hash);
	Log3($name, 4, "RLC($name): auto-after-timer $duration");
}

sub RLCtrl_autoTimer($)
{
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	Log3($name, 3, "RLC($name): auto by timer");
	RLCtrl_auto($hash);
}

# ----------------------------------------------------------------------
# little helper functions

sub RLCtrl_stateicon($) {
	my $hash = $defs{$_[0]};
	return ".*:time_automatic:on" if $hash->{MODE} eq "auto";
	return ".*:light_light_dim_00:auto" if ReadingsVal($hash->{NAME}, "pct", 0) == 0;
	my $v = sprintf("%02d", int(($hash->{MAN_BRI}/10.0)+0.5)*10);
	my $c = CommandGet("","$hash->{LIGHTDEV} rgb");
	return ".*:light_light_dim_$v\@#$c:off";
}

sub RLCattr($$)
{
	my ($name, $aname) = @_;

	$name = $name->{NAME} if ref($name) eq "HASH";
	return AttrVal($name, $aname, $RLCtrl_attrs{$aname}->{dflt} || "");
}

sub RLCtrl_good_time($$$)
{
	my ($hash, $str, $where) = @_;
	my $name = $hash->{NAME};

	if ($str !~ /^[0-2][0-9]:[0-5][0-9]$/) {
		Log3($name, 2, "RLC($name): bad time spec '$str' in $where");
		return 0;
	}
	return 1;
}

sub RLCtrl_gettime()
{
	my @t = localtime(gettimeofday());
	my $str = sprintf("%02d:%02d", $t[2], $t[1]);
	my $min = $t[2]*60 + $t[1];
	return ($str, $min);
}
	
sub RLCtrl_isin($@)
{
	my $elt = shift;
	return scalar(grep { $_ eq $elt } @_) != 0;
}

1;

=pod
=item device
=item summary   Romans Light Controller
=item summary_DE Romans Lichtcontroller

=begin html
<a name="RLCtrl"></a>
<h3>RLCtrl</h3>
<ul>

  RLCtrl tries to be an all-in-one controller for lights, saving the need for
  auxiliary DOIF or dummy devices and also many notifies.
  <br>

  RLCtrl has a so-called "auto" mode, where the light is turned on by motion
  events, and brightness and color temperature can be automatically selected
  controlled by some parameters.
  <br>

  Additionally there's a "manual" mode, where brightness + temperature can
  be set by FHEM commands, and the light doesn't go off after some time.
  <br>

  You can also store "scenes" in an RLCtrl device, which usually means to
  apply certain settings to the light device. But essentially you can call any
  FHEM command when entering a scene.
  <br>

  <a name="RLCtrl_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RLCtrl &lt;lightdev&gt; &lt;motionsensor&gt; [&lt;lightsensor&gt;]</code><br>
    <br>
  </ul><br>

  <a name="RLCtrl_Readings"></a>
  <b>Readings</b>
  <ul>
  </ul><br>
   
  <a name="RLCtrl_Set"></a>
  <b>Set</b>
  <ul>
  </ul><br>
   
  <a name="RLCtrl_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="RLCtrl_Attr"></a>
  <b>Attr</b>
  <ul>

    <li>motionOnTime<br>
      How long a motion event should turn on the light, in seconds.
	  Default: 240s
    </li>

    <li>maxAutoBrightness<br>
      This is the maximum brightness to use in Auto mode, default is 100. This
      can be reduced if full brightness should be available only in manual
	  mode or with certain scenes.
    </li>

    <li>manualTimeout<br>
      If manual mode has been active for this many seconds, RLCtrl falls back
      to auto mode; default is 6 houts. The intention is to avoid having the
      light on forever if you forget your manual mode setting.
    </li>

    <li>checkInterval<br>
      RLCtrl recalculates brightness, color temperature etc. at least in this
      interval by timer, even if there are no other events. Default: 5 minutes.
    </li>

    <li>luxTheshH, luxTheshL<br>
      If a lightsensor device is defined, these attributes define how dark it
      has to be for the light to be turned on, and how fast it will reach
      full brightness.<br>
	  If the effective lux value (see below, lightFeedback) drops to or below
      luxThreshH, the lights will be turned on. The brightness linearly
      increases until luxThreshL is reached, at which point the brightness
      will be maxAutoBrightness.<br>
      Defaults are 60 and 20 lux, resp. Probably you will need to adapt these
      values to your personal needs.
    </li>

    <li>lightFeedback<br>
      This floating-point value is a factor to calculate an "effective lux"
      value from the measurement by the light sensor device. It is meant to
      compensate for the amount of light that comes from the controlled light
      device itself to the sensor. Default is 0.5, but it will often need
      adjustment.<br>
      If you notice that the light becomes a bit darker after a minute or so
      (when the sensors sends its next event) then the feedback factor is too
      small. On the other hand, if it becomes brighter the factor is too
      large. Ideally, you should not see a noticable change, no matter what
      the relations of ambient and artifical light are.<br>
      A good first guess can be derived from the light sensor's raw reading
      after the light is turned on in auto mode at night, i.e. if there's no
      other ambient light. The estimation is then this reading divided by
      maxAutoBrightness (usually 100). For example, if the light goes to
      max. brightness and the sensor next reports 150lux, you can start
      with a factor of 1.5.
    </li>

    <li>nightTime, nightLevel<br>
      The nightTime attribute defines a time window by two HH:MM values.
      Between these two times, auto mode won't use the normal brightness
      calculation, but will use nightLevel as target brightness.<br>
      The intention is to (drastically) reduce brightness during night time,
      when normal illumination is not wanted but instead a heavily dimmed
      orientiation light.<br>
	  Default nightLevel is 10, and there's no default for nightTime. You have
	  to turn it on intentionally.
    </li>

    <li>dayTime<br>
      When during dayTime, the light won't be turned on at all.
    </li>

    <li>ctTimes<br>
      This attribute can contain two or three HH:MM times that control color
      temperature selection of RLCtrl. The basic idea behind that is to use
      a cold white during daytime, and a warm one for the night.<br>
      The first time is when to switch from night mode to day mode, i.e. from
      the warmest color to the coldest.<br>
      If two times are given, the second is vice versa the time to switch from
      cold to warm white.<br>
      If there are three times, RLCtrl gradually changes from cold to warm
      white in the time window between the 2nd and the 3rd time.<br>
	  There is no default for ctTimes, you have to set it explicitly to turn
	  on the feature.<br>
      Example:<br>
        <code>07:00 19:00 22:00</code>: change from warm to cold at 07:00,
        and start changing back to warm at 19:00. The temperature decreases
        (becomes warmer) for 3h until 22:00, where it reaches the warmest
        tone.<br>
      This feature is currently heavily modeled for my personal needs and
      preferences. I won't mind patches for different warm/cold models ;-)
    </li>

    <li>ctMin, ctMax<br>
      The minimum and maximum color temperature to use.
 	  Defaults: 2400K and 6000K.
    </li>

    <li>motionEvent<br>
      This is the event pattern for the motion sensor which triggers the
      light in auto mode. Default: "state: *motion".
    </li>

    <li>lightEvent<br>
      This is the event pattern for the light sensor to listen to. Default: "lux:.*".
    </li>

    <li>lightReading<br>
      This is the reading of the light sensor device which gives the lux
=value. Default: "lux".
    </li>

  </ul><br>

</ul><br>

=end html

=begin html_DE
<a name="RLCtrl"></a>
=end html

=cut
