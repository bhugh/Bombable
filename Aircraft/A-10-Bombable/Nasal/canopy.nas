# used to the animation of the canopy switch and the canopy move
# toggle keystroke or 2 position switch

var cnpy = aircraft.door.new("canopy", 10);
var switch = props.globals.getNode("sim/model/A-10/controls/canopy/canopy-switch", 1);
var pos = props.globals.getNode("canopy/position-norm", 1);

var canopy_switch = func(v) {

	var p = pos.getValue();

	if (v == 2 ) {
		if ( p < 1 ) {
			v = 1;
		} elsif ( p >= 1 ) {
			v = -1;
		}
	}

	if (v < 0) {
		switch.setValue(1);
		cnpy.close();

	} elsif (v > 0) {
		switch.setValue(3);
		cnpy.open();

	}
}

# fixes cockpit when use of ac_state.nas #####
var cockpit_state = func {
	var switch = getprop("sim/model/A-10/controls/canopy/canopy-switch");
	if ( switch == 1 ) {
		setprop("canopy/position-norm", 0);
	}
}

