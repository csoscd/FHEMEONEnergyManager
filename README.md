# FHEMEONEnergyManager
FHEM Module for Eon EnergyManager (= SolarWatt)

## Figures delivered by EnergyManager:

BATTERY_CHARGE: Current battery charge state in percent

BATTERY_POWERIN: Same as LOC_P_BUFFERED_FROM_PRODUCERS, currently going to the battery

BATTERY_POWEROUT: Currently consumed from the battery

BATTERY_STATE: Status of the battery

BATTERY_TEMPERATURE: Current temperature of the battery

LOC_P_BUFFERED_FROM_PRODUCERS: Currently going to the battery

LOC_P_CONSUMED: Current consumption

LOC_P_PRODUCED: Current production

LOC_P_OUT: Currently going to the net

LOC_P_IN: Currently consumed from the net

LOC_P_SELF_CONSUMED: Currently self consumed. This includes real consumption as well as loading the battery as well as from the battery

LOC_P_CONSUMED_FROM_STORAGE: Currently consumed from the battery

LOC_W_CONSUMED: Overall consumption

LOC_W_IN: Overall consumed from the net (Stromzukauf)

LOC_W_SELF_SUPPLIED: Overall consumption from own supplier (include battery and direct production ?) (Selbstversorgung)

LOC_W_OUT: Overall gone to the net (differs for me from value shown in EON App)

LOC_W_PRODUCED: Overall produced

LOC_W_BUFFERED_FROM_PRODUCERS: Overall gone to battery
