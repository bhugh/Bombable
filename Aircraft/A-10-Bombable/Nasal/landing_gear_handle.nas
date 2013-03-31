##
# Override generic gear handling.
#
controls.gearDown = func(v) {
	#print("A-10 gear handling.", v);
	var gearHandlerGoal = nil;
	if((v == -1) and !getprop("/gear/gear[1]/wow") and (electrical.DC_ESSEN_bus_volts >= 23)) {  # handler gear up
		gearHandlerGoal = 0.0;
	} elsif(v == 1) {
		gearHandlerGoal = -1; }
	if(gearHandlerGoal != nil) {
		# Cockpit handler gear animation
		interpolate(props.globals.getNode("/sim/model/A-10/controls/gear/ld-gear-handle-anim", 1), gearHandlerGoal, 2);
		# Landing gear animation
		if((gearHandlerGoal == 0.0) and (getprop("/systems/A-10-hydraulics/hyd-psi[0]") >= 900)) { # up gear
			setprop("/controls/gear/gear-down", 0);
		} elsif((gearHandlerGoal == -1) and (getprop("/systems/A-10-hydraulics/hyd-psi[0]") >= 900)) {
			setprop("/controls/gear/gear-down", 1);
		}
	}
}

# Auxiliary landing gear extension (in case of left hydraulic system failure):
# First: place the landing gear handle DOWN,
# then pull up AUX LG EXT handle
var aux_lg_extension = func() {
	print("aux_lg_extension called.");
	if((getprop("/sim/model/A-10/controls/gear/ld-gear-handle-anim") == -1) and (getprop("/systems/A-10-hydraulics/hyd-psi[0]") < 900) and (getprop("/systems/A-10-hydraulics/aux-lg-ext-accumulator") >= 900) and (getprop("/sim/model/A-10/controls/gear/aux-lg-ext"))) {
		setprop("/systems/A-10-hydraulics/aux-lg-ext-accumulator", 0.0);
		setprop("/controls/gear/gear-down", 1);
	}
}

a10initprop="/sim/a10-landing-initialized";
var inited=getprop (a10initprop);
setprop(a10initprop,1);
if (!inited) { 
    print ("Initializing Landing Gear");

    setlistener("/sim/model/A-10/controls/gear/aux-lg-ext", aux_lg_extension);
}