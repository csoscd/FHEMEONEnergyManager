#
# 78_EONEnergyManager.pm
# The API 
#

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;
use warnings;
use Time::Local;
use POSIX qw( strftime );
use HttpUtils;
use JSON qw( decode_json );

my $MODUL = "EONEnergyManager";

###############################################
# Help Function to have a standard logging
#
#
# begin EONEnergyManager_Log
#
sub EONEnergyManager_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/EONEnergyManager_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}
#
# end EONEnergyManager_Log
###############################################

###############################################
# Convert from one possible unit to another. Maybe not the most graceful way
# however, it works :-)
#
#
# begin EONEnergyManager_ConvertData
#
sub EONEnergyManager_ConvertData($$$$) {
        my ($hash, $data, $sourceunit, $targetunit) = @_;
	my $name = $hash->{NAME};

	EONEnergyManager_Log($hash, 5, "$name: Getting ConvertData for $data with source unit $sourceunit into targetunit $targetunit");

        my $rv;
        my @cv;

        $cv[0][0] = 'W';
        $cv[0][1] = 'kW';
        $cv[0][2] = 'MW';
        $cv[0][3] = 'GW';
        $cv[0][4] = 0.001;

        $cv[1][0] = 'GW';
        $cv[1][1] = 'MW';
        $cv[1][2] = 'kW';
        $cv[1][3] = 'W';
        $cv[1][4] = 1000;

        $cv[2][0] = 'Wh';
        $cv[2][1] = 'kWh';
        $cv[2][2] = 'MWh';
        $cv[2][3] = 'GWh';
        $cv[2][4] = 0.001;

        $cv[3][0] = 'GWh';
        $cv[3][1] = 'MWh';
        $cv[3][2] = 'kWh';
        $cv[3][3] = 'Wh';
        $cv[3][4] = 1000;

        my $i = 0;
        my $j = 0;
        my $sourceindex_dir = -1;
        my $sourceindex_val = -1;
        my $targetindex_dir = -1;
        my $targetindex_val = -1;
        my $isFinished = 0;
        while ($i < 4 && $isFinished == 0) {
                $j = 0;
                while ($j < 4) {
                        if ($cv[$i][$j] eq $sourceunit) {
                                $sourceindex_dir = $i;
                                $sourceindex_val = $j;
                        } elsif ($cv[$i][$j] eq $targetunit) {
                                $targetindex_dir = $i;
                                $targetindex_val = $j;
                        }
                        $j++;
                }
                if ($sourceindex_val < $targetindex_val && $sourceindex_val != -1 && $targetindex_val != -1) {
                        my $k = $sourceindex_val;
                        while ($k < $targetindex_val) {
                                $data = $data * $cv[$i][4];
                                $k++;
                        }
                        $isFinished = 1;
                }
                $i++;
        }

	EONEnergyManager_Log($hash, 5, "$name: Getting ConvertData finished, new data $data with source unit $sourceunit into targetunit $targetunit");

        $rv = $data;
        return $rv;

}
#
# end EONEnergyManager_ConvertData
###############################################

###############################################
# begin EONEnergyManager_Initialize
#
sub EONEnergyManager_Initialize($) {

    my ($hash) = @_;
    my $TYPE = "EONEnergyManager";

    $hash->{DefFn}    = $TYPE . "_Define";
    $hash->{UndefFn}  = $TYPE . "_Undefine";
    $hash->{SetFn}    = $TYPE . "_Set";
    $hash->{GetFn}    = $TYPE . "_Get";
    $hash->{NotifyFn} = $TYPE . "_Notify";

    $hash->{NOTIFYDEV} = "global";

    $hash->{DbLog_splitFn}= $TYPE . "_DbLog_splitFn";
#    $hash->{AttrFn}       = $TYPE . "_Attr";


 $hash->{AttrList} = ""
    . "disable:1,0 "
    . "interval "
    . "interval_night "
    . $readingFnAttributes
  ;
}
#
# end EONEnergyManager_Initialize
###############################################

###############################################
# begin EONEnergyManager_Define
#
sub EONEnergyManager_Define($$) {

    my ($hash, $def) = @_;
    my @args = split("[ \t][ \t]*", $def);

    return "Usage: define <name> EONEnergyManager <host>" if(@args <2 || @args >3);

    my $name = $args[0];
    my $type = "EONEnergyManager";
    my $interval = 60;
    my $host = $args[2];

    $hash->{NAME} = $name;

    $hash->{STATE}    = "Initializing" if $interval > 0;
    $hash->{HOST}     = $host;
    $hash->{APIURL}   = "http://".$host."/rest/kiwigrid/wizard/devices";
    $hash->{helper}{INTERVAL} = $interval;
    $hash->{MODEL}    = $type;
    
  #Clear Everything, remove all timers for this module
  RemoveInternalTimer($hash);
  
  # Starting the timer to get data from the energy manager.
  InternalTimer(gettimeofday() + 10, "EONEnergyManager_GetData", $hash, 0);

  #
  # Init global variables for units from attr
  # InternalTimer(gettimeofday() + 10, "FroniusSymJSON_InitAttr", $hash, 0);

  #Reset temporary values
  #$hash->{fhem}{jsonInterpreter} = "";

  $hash->{fhem}{modulVersion} = '$V0.0.2$';
 
  return undef;
}
#
# end EONEnergyManager_Define
###############################################

###############################################
# begin EONEnergyManager_GetData
#
sub EONEnergyManager_GetData($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $interval = EONEnergyManager_getInterval($hash);

	EONEnergyManager_Log($hash, 5, "$name: Getting data from base url from $hash->{APIURL}");

	EONEnergyManager_PerformHttpRequest($hash, $hash->{APIURL}, "DATA");

	# Now add a next timer for getting the data
	InternalTimer(gettimeofday() + $interval, "EONEnergyManager_GetData", $hash, 0);
}
#
# end EONEnergyManager_GetData
###############################################

###############################################
# begin EONEnergyManager_GetData_Parse
#
#
# Parses the data that was received by a request
#
sub EONEnergyManager_GetData_Parse($$$) {
	my ($hash, $data, $call) = @_;
	my $name = $hash->{NAME};

	my $rv = 0;

	#my $json = decode_json($data);

}
#
# end EONEnergyManager_GetData_Parse
###############################################

###############################################
# begin EONEnergyManager_PerformHttpRequest
#
#
# Perform the http request as a non-blocking request
#
sub EONEnergyManager_PerformHttpRequest($$)
{
    my ($hash, $url, $callname) = @_;
    my $name = $hash->{NAME};
    my $param = {
                    url        => $url,
                    timeout    => 5,
                    hash       => $hash,                                                                                 # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                    method     => "GET",                                                                                 # Lesen von Inhalten
                    header     => "User-Agent: EONEnergyManager/1.0.0\r\nAccept: application/json",                            # Den Header gemäß abzufragender Daten ändern
                    callback   => \&EONEnergyManager_ParseHttpResponse,                                                    # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                    call       => $callname
                };

    EONEnergyManager_Log($hash, 5, "$name: Executing non-blocking get for $url");

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 
}
#
# end EONEnergyManager_PerformHttpRequest
###############################################

###############################################
# begin EONEnergyManager_ParseHttpResponse
#
sub EONEnergyManager_ParseHttpResponse($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $interval = EONEnergyManager_getInterval($hash);

    if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        EONEnergyManager_Log($hash, 1, "error while requesting ".$param->{url}." - $err");                                            # Eintrag fürs Log
	if ($param->{call} eq "DATA") {
	  #
	  # if DATA Call failed, try again in 60 seconds
	  #
	  InternalTimer(gettimeofday() + 60, "EONEnergyManager_GetData", $hash, 0);
	  $hash->{STATE}    = "Connection error getting API info";
	  EONEnergyManager_Log($hash, 1, "DATA call to EnergyManager failed");                                                         # Eintrag fürs Log
	} else {
	  EONEnergyManager_Log($hash, 1, "Call to EnergyManager failed for ".$param->{call}. "(".$param->{url}.")");                                                         # Eintrag fürs Log
	}
    }
    elsif($data ne "")                                                                                                  # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {
        EONEnergyManager_Log($hash, 5, "url ".$param->{url}." returned: $data");                                                         # Eintrag fürs Log

	if ($param->{call} eq "DATA") {
		#
		# This is the standard data call
		# 
		EONEnergyManager_GetData_Parse($hash, $data, $param->{call});
	} else {
		EONEnergyManager_Log($hash, 1, "Error. Unknown call for ".$param->{call}); 
	}
    }
    
    # Damit ist die Abfrage zuende.
    # Evtl. einen InternalTimer neu schedulen
}
#
# end EONEnergyManager_ParseHttpResponse
###############################################


###############################################
# begin EONEnergyManager_getInterval
#
#
# Helper function to the a valid interval value for data requests
#
sub EONEnergyManager_getInterval($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $is_day = isday();

	my $interval = $attr{$name}{interval};
	# if there is no interval given, use the internal default
	if ($interval eq "") {
		# use default interval if none is given
		$interval = $hash->{helper}{INTERVAL};
	}
	
	# check if sun has gone. If yes and a night interval is set, use the night interval
	if ($is_day eq "0") {
		my $interval_night = $attr{$name}{interval_night};
		if ($interval_night ne "") {
			$interval = $interval_night;				
		}
	}

	# if interval is less then 5, we will use ten seconds as minimum
	if ($interval < 5) {
		# the minimum value
		$interval = 10;
		$attr{$name}{interval} = 10;
	}
	
	$hash->{helper}{last_used_interval} = $interval;
	$hash->{helper}{last_is_day} = $is_day;
	
	return $interval;
}
#
# end EONEnergyManager_getInterval
###############################################

###############################################
# begin EONEnergyManager_DbLog_splitFn
#
sub EONEnergyManager_DbLog_splitFn($) {
  my ($event) = @_;
  my ($reading, $value, $unit) = "";

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];
  
  $unit = "";
#  $unit = $unit_day if($reading =~ /ENERGY_DAY.*/);;
#  $unit = $unit_current if($reading =~ /ENERGY_CURRENT.*/);;
#  $unit = $unit_total if($reading =~ /ENERGY_TOTAL.*/);;
#  $unit = $unit_year if($reading =~ /ENERGY_YEAR.*/);  

  Log3 "dbsplit", 5, "EONEnergyManager dbsplit: ".$event."  $reading: $value $unit" if(defined($value));
  Log3 "dbsplit", 5, "EONEnergyManager dbsplit: ".$event."  $reading" if(!defined($value));

  return ($reading, $value, $unit);
}
#
# end EONEnergyManager_DbLog_splitFn
###############################################

###############################################
# begin EONEnergyManager_Set
#
sub EONEnergyManager_Set($$@) {
}
#
# end EONEnergyManager_Set
###############################################


###############################################
# begin EONEnergyManager_Get
#
sub EONEnergyManager_Get($@) {
}
#
# end EONEnergyManager_Get
###############################################

###############################################
# begin EONEnergyManager_Undefine
#
sub EONEnergyManager_Undefine($$) {
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
} # end FroniusSymJSON_Undefine
#
# end EONEnergyManager_Undefine
###############################################

###############################################
# begin EONEnergyManager_Notify
#
sub EONEnergyManager_Notify($$)
{
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash

	EONEnergyManager_Log $own_hash, 5, "Getting notify $ownName / $dev_hash->{NAME}";
 
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		 EONEnergyManager_InitAttr($own_hash);
	}
}
#
# end EONEnergyManager_Notify
###############################################

###############################################
# begin EONEnergyManager_InitAttr
#
sub EONEnergyManager_InitAttr($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	EONEnergyManager_Log $hash, 1, "Initialising user setting (attr) for $name";
	
	if ($init_done) {
		if (defined $attr{$name}{unit_day}) {
#			$unit_day = $attr{$name}{unit_day};
		} else {
#			$unit_day = "Wh";
			EONEnergyManager_Log $hash, 5, "attr unit_day not set, using default";
		}
		if (defined $attr{$name}{unit_current}) {
#			$unit_current = $attr{$name}{unit_current};
		} else {
#			$unit_current = "W";
			EONEnergyManager_Log $hash, 5, "attr unit_current not set, using default";
		}
		if (defined $attr{$name}{unit_total}) {
#			$unit_total = $attr{$name}{unit_total};
		} else {
#			$unit_total = "Wh";
			EONEnergyManager_Log $hash, 5, "attr unit_total not set, using default";
		}
		if (defined $attr{$name}{unit_year}) {
#			$unit_year =  $attr{$name}{unit_year};
		} else {
#			$unit_year =  "Wh";
			EONEnergyManager_Log $hash, 5, "attr unit_year not set, using default";
		}
		EONEnergyManager_Log $hash, 5, "User setting (attr) initialised for $name";
	} else {
		EONEnergyManager_Log $hash, 1, "Fhem not ready yet, retry in 5 seconds";
	  	InternalTimer(gettimeofday() + 5, "EONEnergyManager_InitAttr", $hash, 0);
	}
}
#
# end EONEnergyManager_InitAttr
###############################################


###############################################
# begin EONEnergyManager_GetUpdate
#
sub EONEnergyManager_GetUpdate($) {

}
#
# end EONEnergyManager_GetUpdate
###############################################

###############################################
# begin EONEnergyManager_UpdateAborted
#
sub EONEnergyManager_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  my $host = $hash->{HOST};
  EONEnergyManager_Log $hash, 1, "Timeout when connecting to host $host";

} 
#
# end EONEnergyManager_UpdateAborted
###############################################


# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary This module can be used to access data from the E.ON Energy Manager. As the E.ON module should be similar to SOLARWATT Energy Manager it might be used for that as well.
=item summary_DE Mit diesem Modul kann auf die Daten des E.ON Energy Managers zugegriffen werden. Da das E.ON Modul baugleich mit dem SOLARWATT Energy Manager ist, könnte es genauso dafür funktionieren.

=begin html
 Englische Commandref in HTML
=end html

=begin html_DE
 Deustche Commandref in HTML
=end html

# Ende der Commandref
=cut
