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

my $batterie_work = 0;

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
    . "powerperbatterie "
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

	my $json = decode_json($data);

	if (defined $json->{'result'}->{'items'}) {
		my $batteryCharge;
		my $batteryHealth;
		my $batteryPowerIn;
		my $batteryPowerOut;
		my $batteryTemp;
		my $batteryState;
		my $batteryCount;
		
		my $smPowerIn;
		my $smPowerOut;
		my $smWorkIn;
		my $smWorkOut;

		my $locWorkConsumedFromStorage;
		my $locWorkSelfSupplied;
		my $locWorkProduced;
		my $locWorkOut;
		my $locWorkOutFromProducers;
		my $locWorkIn;
		my $locWorkBuffered;
		my $locWorkReleased;
		my $locWorkBufferedFromProducers;
		my $locWorkConsumedFromProducers;
		my $locWorkConsumedFromGrid;
		my $locWorkSelfConsumed;
		my $locWorkOutFromStorage;
		my $locWorkBufferedFromGrid;
		my $locWorkConsumed;

		my $locPowerConsumedFromGrid;
		my $locPowerProduced;
		my $locPowerOut;
		my $locPowerConsumedFromStorage;
		my $locPowerBufferedFromProducers;
		my $locPowerOutFromStorage;
		my $locPowerSelfSupplied;
		my $locPowerOutFromProducers;
		my $locPowerBufferedFromGrid;
		my $locPowerConsumed;
		my $locPowerIn;
		my $locPowerConsumptionForecastNow;
		my $locPowerProductionForecastNow;					
		my $locPowerReleased;					
		my $locPowerConsumedFromProducers;
		my $locPowerSelfConsumed;

	
	
		my @items = @{ $json->{'result'}->{'items'} };
		foreach my $item (@items) {
			my $guid = $item->{'guid'};
			if (EONEnergyManager_Begins_With($guid, "urn:solarwatt:myreserve:bc:")) {
				EONEnergyManager_Log($hash, 5, "Result: ".$item->{'guid'});

				# Ladezustand
				EONEnergyManager_Log($hash, 5, "Battery-StateOfCharge: ".$item->{'tagValues'}->{'StateOfCharge'}->{'value'});
				$batteryCharge = $item->{'tagValues'}->{'StateOfCharge'}->{'value'};

				# Anzahl der Batterien
				EONEnergyManager_Log($hash, 5, "Battery-CountBatteryModules: ".$item->{'tagValues'}->{'CountBatteryModules'}->{'value'});
				$batteryCount = $item->{'tagValues'}->{'CountBatteryModules'}->{'value'};
			
				# Healthy-Status
				EONEnergyManager_Log($hash, 5, "Battery-StateOfHealth: ".$item->{'tagValues'}->{'StateOfHealth'}->{'value'});
				$batteryHealth = $item->{'tagValues'}->{'StateOfHealth'}->{'value'};
				
				# Eingangsleistung in Watt
				EONEnergyManager_Log($hash, 5, "Battery-PowerACIn: ".$item->{'tagValues'}->{'PowerACIn'}->{'value'});
				$batteryPowerIn = $item->{'tagValues'}->{'PowerACIn'}->{'value'};
				
				# Strom aus Batterie in Watt
				EONEnergyManager_Log($hash, 5, "Battery-PowerACOut: ".$item->{'tagValues'}->{'PowerACOut'}->{'value'});
				$batteryPowerOut = $item->{'tagValues'}->{'PowerACOut'}->{'value'};
				
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-CurrentBatteryIn: ".$item->{'tagValues'}->{'CurrentBatteryIn'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-CurrentBatteryOut: ".$item->{'tagValues'}->{'CurrentBatteryOut'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-WorkACIn: ".$item->{'tagValues'}->{'WorkACIn'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-WorkACOut: ".$item->{'tagValues'}->{'WorkACOut'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageGRMOut: ".$item->{'tagValues'}->{'VoltageGRMOut'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageGRMIn: ".$item->{'tagValues'}->{'VoltageGRMIn'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-CurrentGRMOut: ".$item->{'tagValues'}->{'CurrentGRMOut'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-ResistanceBatteryMean: ".$item->{'tagValues'}->{'ResistanceBatteryMean'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-ResistanceBatteryMax: ".$item->{'tagValues'}->{'ResistanceBatteryMax'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-ResistanceBatteryMin: ".$item->{'tagValues'}->{'ResistanceBatteryMin'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageBatteryCellMax: ".$item->{'tagValues'}->{'VoltageBatteryCellMax'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageBatteryCellMean: ".$item->{'tagValues'}->{'VoltageBatteryCellMean'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageBatteryCellMin: ".$item->{'tagValues'}->{'VoltageBatteryCellMin'}->{'value'});
				# Eingangsleistung ?
				EONEnergyManager_Log($hash, 5, "Battery-VoltageBatteryString: ".$item->{'tagValues'}->{'VoltageBatteryString'}->{'value'});
				
				# Batterietemperatur
				EONEnergyManager_Log($hash, 5, "Battery-TemperatureBattery: ".$item->{'tagValues'}->{'TemperatureBattery'}->{'value'});
				$batteryTemp = $item->{'tagValues'}->{'TemperatureBattery'}->{'value'};
				
				# StateDevice
				EONEnergyManager_Log($hash, 5, "Battery-StateDevice: ".$item->{'tagValues'}->{'StateDevice'}->{'value'});
				$batteryState = $item->{'tagValues'}->{'StateDevice'}->{'value'};
				
				# IdFirmware
				EONEnergyManager_Log($hash, 5, "Battery-IdFirmware: ".$item->{'tagValues'}->{'IdFirmware'}->{'value'});
			} elsif ($guid eq "ERC04-000005285_xxx") {
			
			} elsif ($guid eq "52a92c37-40e7-4a5d-8b1e-82ee6bad5661_xxx") {
				# Leistungsmessung (Stromgzaehler)
				# 52a92c37-40e7-4a5d-8b1e-82ee6bad5661
			
			} elsif ($guid eq "urn:forecast:ERC04-000005285_xxx") {
				# Leistungsmessung (Stromgzaehler)
				# 
			
			} elsif (EONEnergyManager_Begins_With($guid, "urn:sunspec:fronius:inverter:_xxx")) {
				# Fronius Wechselrichter
			} elsif ($guid eq "urn:kiwigrid:location:ERC04-000005285:0_xxx") {
				# DeviceClass: com.kiwigrid.devices.location.Location
				# Location
				# WorkProduced = gesamte Produktion
				# WorkOut = gesamte Einspeisung
				# WorkIn = gesamter Bezug
				# WorkBuffered = ?
				# WorkReleased = ?
				# WorkConsumed = gesamter Verbauch
				# WorkConsumedFromStorage = gesamter Verbrauch aus Speicher
				# WorkConsumedFromGrid = ?
				# WorkSelfConsumed = ?
				# WorkOutFromStorage = ?
				# WorkBufferedFromGrid = ?
				# WorkBufferedFromProducers = ?
			} else {
			        my $isPowerMeter = 0;
			        my $isLocation = 0;
				my @devices = @{ $item->{'deviceModel'} };
				foreach my $device (@devices) {
					EONEnergyManager_Log($hash, 5, "DeviceClass: ".$device->{'deviceClass'});
					if ($device->{'deviceClass'} eq "com.kiwigrid.devices.powermeter.PowerMeter") {
						$isPowerMeter = 1;
					} elsif ($device->{'deviceClass'} eq "com.kiwigrid.devices.location.Location") {
					        $isLocation = 1;
					}
				}
				
				if ($isLocation == 1) {
					$locWorkConsumedFromStorage = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkConsumedFromStorage'}->{'value'}, "Wh", "kWh"));
					$locWorkSelfSupplied = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkSelfSupplied'}->{'value'}, "Wh", "kWh"));
					$locWorkProduced = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkProduced'}->{'value'}, "Wh", "kWh"));
					$locWorkOut = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkOut'}->{'value'}, "Wh", "kWh"));
					$locWorkOutFromProducers = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkOutFromProducers'}->{'value'}, "Wh", "kWh"));
					$locWorkIn = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkIn'}->{'value'}, "Wh", "kWh"));
					$locWorkBuffered = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkBuffered'}->{'value'}, "Wh", "kWh"));
					$locWorkReleased = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkReleased'}->{'value'}, "Wh", "kWh"));
					$locWorkBufferedFromProducers = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkBufferedFromProducers'}->{'value'}, "Wh", "kWh"));
					$locWorkConsumedFromProducers = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkConsumedFromProducers'}->{'value'}, "Wh", "kWh"));
					$locWorkConsumedFromGrid = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkConsumedFromGrid'}->{'value'}, "Wh", "kWh"));
					$locWorkSelfConsumed = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkSelfConsumed'}->{'value'}, "Wh", "kWh"));
					$locWorkOutFromStorage = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkOutFromStorage'}->{'value'}, "Wh", "kWh"));
					$locWorkBufferedFromGrid = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkBufferedFromGrid'}->{'value'}, "Wh", "kWh"));
					$locWorkConsumed = sprintf("%.4f", EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkConsumed'}->{'value'}, "Wh", "kWh"));

					$locPowerConsumedFromGrid = $item->{'tagValues'}->{'PowerConsumedFromGrid'}->{'value'};
					$locPowerProduced = $item->{'tagValues'}->{'PowerProduced'}->{'value'};
					$locPowerOut = $item->{'tagValues'}->{'PowerOut'}->{'value'};
					$locPowerConsumedFromStorage = $item->{'tagValues'}->{'PowerConsumedFromStorage'}->{'value'};
					$locPowerBufferedFromProducers = $item->{'tagValues'}->{'PowerBufferedFromProducers'}->{'value'};
					$locPowerOutFromStorage = $item->{'tagValues'}->{'PowerOutFromStorage'}->{'value'};
					$locPowerSelfSupplied = $item->{'tagValues'}->{'PowerSelfSupplied'}->{'value'};
					$locPowerOutFromProducers = $item->{'tagValues'}->{'PowerOutFromProducers'}->{'value'};
					$locPowerBufferedFromGrid = $item->{'tagValues'}->{'PowerBufferedFromGrid'}->{'value'};
					$locPowerConsumed = $item->{'tagValues'}->{'PowerConsumed'}->{'value'};
					$locPowerIn = $item->{'tagValues'}->{'PowerIn'}->{'value'};
					$locPowerConsumptionForecastNow = $item->{'tagValues'}->{'PowerConsumptionForecastNow'}->{'value'};
					$locPowerProductionForecastNow = $item->{'tagValues'}->{'PowerProductionForecastNow'}->{'value'};					
					$locPowerReleased = $item->{'tagValues'}->{'PowerReleased'}->{'value'};					
					$locPowerConsumedFromProducers = $item->{'tagValues'}->{'PowerConsumedFromProducers'}->{'value'};
					$locPowerSelfConsumed = $item->{'tagValues'}->{'PowerSelfConsumed'}->{'value'};
					
				} elsif ($isPowerMeter == 1) {
					$smPowerIn = $item->{'tagValues'}->{'PowerIn'}->{'value'};
					$smPowerOut = $item->{'tagValues'}->{'PowerOut'}->{'value'};
					$smWorkIn = EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkIn'}->{'value'}, "Wh", "kWh");
					$smWorkOut = EONEnergyManager_ConvertData($hash, $item->{'tagValues'}->{'WorkOut'}->{'value'}, "Wh", "kWh");
					EONEnergyManager_Log($hash, 5, "Reading SmartMeter values: ".$smPowerIn."W, ".$smPowerOut."W, ".$smWorkIn." kWh, ".$smWorkOut." kWh");
				}
				
			}
			
			
			
#			my @tagvalues = @{ $item->{'tagValues'} };
#			foreach my $tagvalue (@tagvalues) {
#			
#			}
			

		}
		
		my $day_start_work_in = EONEnergyManager_GetStartValue($hash, "W_IN", $locWorkIn);
		my $day_start_work_out = EONEnergyManager_GetStartValue($hash, "W_OUT", $locWorkOut);
		my $day_start_work_consumed = EONEnergyManager_GetStartValue($hash, "W_CONSUMED", $locWorkConsumed);
		my $day_start_work_produced = EONEnergyManager_GetStartValue($hash, "W_PRODUCED", $locWorkProduced);
		my $day_start_work_from_battery = EONEnergyManager_GetStartValue($hash, "W_CONSUMED_FROM_STORAGE", $locWorkConsumedFromStorage);
		my $day_start_work_from_producer = EONEnergyManager_GetStartValue($hash, "W_CONSUMED_FROM_PRODUCER", $locWorkConsumedFromProducers);
		my $day_start_work_to_battery = EONEnergyManager_GetStartValue($hash, "W_BUFFERED", $locWorkBuffered);

		my $day_current_work_in = sprintf("%.4f", $locWorkIn - $day_start_work_in);
		my $day_current_work_out = sprintf("%.4f", $locWorkOut - $day_start_work_out);
		my $day_current_work_consumed = sprintf("%.4f", $locWorkConsumed - $day_start_work_consumed);
		my $day_current_work_produced = sprintf("%.4f", $locWorkProduced - $day_start_work_produced);
		my $day_current_work_from_battery = sprintf("%.4f", $locWorkConsumedFromStorage - $day_start_work_from_battery);
		my $day_current_work_from_producer = sprintf("%.4f", $locWorkConsumedFromProducers - $day_start_work_from_producer);
		my $day_current_work_to_battery = sprintf("%.4f", $locWorkBuffered - $day_start_work_to_battery);
		

		my $batterie_current_work = $batterie_work * $batteryCount * $batteryCharge / 100;
		
		my $batterie_estimation_hours = 0;
		if ($locPowerConsumed > 0) {
			$batterie_estimation_hours = sprintf("%.2f", $batterie_current_work / $locPowerConsumed);
		}
		
		my $now_time = timelocal localtime(time);
		$now_time = $now_time + ($batterie_estimation_hours * 60 * 60);
		my $batterie_estimated_time = strftime "%d.%m.%Y %H:%M", (localtime $now_time);

		my $autarkie = 100;
		if ($locWorkConsumed > 0) {
			$autarkie = sprintf("%.2f", (($locWorkConsumedFromStorage + $locWorkConsumedFromProducers) / $locWorkConsumed * 100));
		}
		
		my $autarkie_today = 100;
		if ($day_current_work_consumed > 0) {
			$autarkie_today = sprintf("%.2f", (($day_current_work_from_battery + $day_current_work_from_producer) / $day_current_work_consumed * 100));
		}

		readingsBeginUpdate($hash);

		$rv = readingsBulkUpdate($hash, "AUTARKIE", $autarkie);
		$rv = readingsBulkUpdate($hash, "AUTARKIE_TODAY", $autarkie_today);

		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_IN", $day_current_work_in);
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_OUT", $day_current_work_out);
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_CONSUMED", $day_current_work_consumed);
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_PRODUCED", $day_current_work_produced);		
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_FROM_BATTERY", $day_current_work_from_battery);		
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_FROM_PRODUCER", $day_current_work_from_producer);		
		$rv = readingsBulkUpdate($hash, "CAL_TODAY_W_TO_BATTERY", $day_current_work_to_battery);		

		$rv = readingsBulkUpdate($hash, "BATTERY_CHARGE", $batteryCharge);
		$rv = readingsBulkUpdate($hash, "BATTERY_POWERIN", $batteryPowerIn);
		$rv = readingsBulkUpdate($hash, "BATTERY_POWEROUT", $batteryPowerOut);
		$rv = readingsBulkUpdate($hash, "BATTERY_HEALTH", $batteryHealth);
		$rv = readingsBulkUpdate($hash, "BATTERY_TEMPERATURE", $batteryTemp);
		$rv = readingsBulkUpdate($hash, "BATTERY_STATE", $batteryState);
		$rv = readingsBulkUpdate($hash, "BATTERY_WORK", $batterie_current_work);
		$rv = readingsBulkUpdate($hash, "BATTERY_ESTIMATED_HOURS", $batterie_estimation_hours);
		$rv = readingsBulkUpdate($hash, "BATTERY_ESTIMATED_END", $batterie_estimated_time);
		
		$rv = readingsBulkUpdate($hash, "SMETER_POWER_IN", $smPowerIn);
		$rv = readingsBulkUpdate($hash, "SMETER_POWER_OUT", $smPowerOut);
		$rv = readingsBulkUpdate($hash, "SMETER_WORK_IN", $smWorkIn);
		$rv = readingsBulkUpdate($hash, "SMETER_WORK_OUT", $smWorkOut);
		
		$rv = readingsBulkUpdate($hash, "LOC_W_CONSUMED_FROM_STORAGE", $locWorkConsumedFromStorage);
		$rv = readingsBulkUpdate($hash, "LOC_W_SELF_SUPPLIED", $locWorkSelfSupplied);
		$rv = readingsBulkUpdate($hash, "LOC_W_PRODUCED", $locWorkProduced);
		$rv = readingsBulkUpdate($hash, "LOC_W_OUT", $locWorkOut);
		$rv = readingsBulkUpdate($hash, "LOC_W_OUT_FROM_PRODUCERS", $locWorkOutFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_W_IN", $locWorkIn);
		$rv = readingsBulkUpdate($hash, "LOC_W_BUFFERED", $locWorkBuffered);
		$rv = readingsBulkUpdate($hash, "LOC_W_RELEASED", $locWorkReleased);
		$rv = readingsBulkUpdate($hash, "LOC_W_BUFFERED_FROM_PRODUCERS", $locWorkBufferedFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_W_CONSUMED_FROM_PRODUCERS", $locWorkConsumedFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_W_CONSUMED_FROM_GRID", $locWorkConsumedFromGrid);
		$rv = readingsBulkUpdate($hash, "LOC_W_SELF_CONSUMED", $locWorkSelfConsumed);
		$rv = readingsBulkUpdate($hash, "LOC_W_OUT_FROM_STORAGE", $locWorkOutFromStorage);
		$rv = readingsBulkUpdate($hash, "LOC_W_BUFFERED_FROM_GRID", $locWorkBufferedFromGrid);
		$rv = readingsBulkUpdate($hash, "LOC_W_CONSUMED", $locWorkConsumed);

		$rv = readingsBulkUpdate($hash, "LOC_P_CONSUMED_FROM_GRID", $locPowerConsumedFromGrid);
		$rv = readingsBulkUpdate($hash, "LOC_P_PRODUCED", $locPowerProduced);
		$rv = readingsBulkUpdate($hash, "LOC_P_OUT", $locPowerOut);
		$rv = readingsBulkUpdate($hash, "LOC_P_CONSUMED_FROM_STORAGE", $locPowerConsumedFromStorage);
		$rv = readingsBulkUpdate($hash, "LOC_P_BUFFERED_FROM_PRODUCERS", $locPowerBufferedFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_P_OUT_FROM_STORAGE", $locPowerOutFromStorage);
		$rv = readingsBulkUpdate($hash, "LOC_P_SELF_SUPPLIED", $locPowerSelfSupplied);
		$rv = readingsBulkUpdate($hash, "LOC_P_OUT_FROM_PRODUCERS", $locPowerOutFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_P_BUFFERED_FROM_GRID", $locPowerBufferedFromGrid);
		$rv = readingsBulkUpdate($hash, "LOC_P_CONSUMED", $locPowerConsumed);
		$rv = readingsBulkUpdate($hash, "LOC_P_IN", $locPowerIn);
		$rv = readingsBulkUpdate($hash, "LOC_P_CONSUMPTION_FORECAST_NOW", $locPowerConsumptionForecastNow);
		$rv = readingsBulkUpdate($hash, "LOC_P_PRODUCTION_FORECAST_NOW", $locPowerProductionForecastNow);					
		$rv = readingsBulkUpdate($hash, "LOC_P_RELEASED", $locPowerReleased);					
		$rv = readingsBulkUpdate($hash, "LOC_P_CONSUMED_FROM_PRODUCERS", $locPowerConsumedFromProducers);
		$rv = readingsBulkUpdate($hash, "LOC_P_SELF_CONSUMED", $locPowerSelfConsumed);
		
		readingsEndUpdate($hash, 1);
	}
}
#
# end EONEnergyManager_GetData_Parse
###############################################

###############################################
# begin EONEnergyManager_GetStartValue
#
sub EONEnergyManager_GetStartValue($$) {

    my ($hash, $para, $value) = @_;
    my $name = $hash->{NAME};


    my $paraname = "EM_START_".$para;

    my $value_today_start = ReadingsVal($name, $paraname, "0:unknown");
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    my $tmp_begin_value;
    my @begin_info = split /:/, $value_today_start;

    if ($begin_info[1] eq $wday) {
	$tmp_begin_value = $begin_info[0];
    } else {
	$tmp_begin_value = $value;
	readingsSingleUpdate($hash, $paraname, $tmp_begin_value.":".$wday, undef);
    }
    return $tmp_begin_value;
}
#
# end EONEnergyManager_GetStartValue
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

    $hash->{STATE}    = "Receiving data";

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

    $hash->{STATE}    = "Data received";

    if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
	$hash->{STATE}    = "Connection error";
        EONEnergyManager_Log($hash, 1, "error while requesting ".$param->{url}." - $err");                                            # Eintrag fürs Log
	if ($param->{call} eq "DATA") {
	  #
	  # if DATA Call failed, try again in 60 seconds
	  #
	  # InternalTimer(gettimeofday() + 60, "EONEnergyManager_GetData", $hash, 0);
	  $hash->{STATE}    = "Connection error getting data";
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
# begin EONEnergyManager_Begins_With
#
#
# Helper Function to check if a string begins with a specific suffix
#
sub EONEnergyManager_Begins_With
{
	if (length($_[0]) >= length($_[1])) {
    	return substr($_[0], 0, length($_[1])) eq $_[1];
	} else {
		return 0;
	}
}
#
# end EONEnergyManager_Begins_With
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

  $unit = "%" if($reading =~ /AUTARKIE.*/);;
  $unit = "%" if($reading =~ /BATTERY_CHARGE.*/);;
  $unit = "W" if($reading =~ /BATTERY_POWERIN.*/);;
  $unit = "W" if($reading =~ /BATTERY_POWEROUT.*/);;
  $unit = "%" if($reading =~ /BATTERY_HEALTH.*/);;
  $unit = "°C" if($reading =~ /BATTERY_TEMPERATURE.*/);;
  $unit = " Wh" if($reading =~ /BATTERY_WORK.*/);;
  $unit = "W" if($reading =~ /SMETER_POWER_.*/);;
  $unit = "kWh" if($reading =~ /SMETER_WORK_.*/);;
  $unit = "W" if($reading =~ /LOC_P_.*/);;
  $unit = "kWh" if($reading =~ /LOC_W_.*/);;
  $unit = "kWh" if($reading =~ /CAL_TODAY_W_.*/);;
  
  
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
		if (defined $attr{$name}{powerperbatterie}) {
			$batterie_work = $attr{$name}{powerperbatterie};
		} else {
			$batterie_work = 2200;
			EONEnergyManager_Log $hash, 5, "attr powerperbatterie not set, using default (2200)";
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
