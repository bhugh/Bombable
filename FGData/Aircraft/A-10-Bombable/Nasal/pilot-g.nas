

var pilot_g            = props.globals.getNode("accelerations/pilot-g", 1);
var timeratio          = props.globals.getNode("accelerations/timeratio", 1);
var pilot_g_damped     = props.globals.getNode("accelerations/pilot-g-damped", 1);
var hud_intens_control = props.globals.getNode("sim/model/A-10/controls/hud/intens", 1);
var hud_alpha          = props.globals.getNode("sim[0]/hud/color/alpha", 1);
var hud_volts          = props.globals.getNode("systems/electrical/outputs/hud", 1);

pilot_g.setDoubleValue(1); 
pilot_g_damped.setDoubleValue(0); 
timeratio.setDoubleValue(0.03); 

var damp = 0;
hud_alpha.setDoubleValue(0);

var update_pilot_g = func {
	var n        = timeratio.getValue(); 
	var g        = pilot_g.getValue();
	var h_intens = hud_intens_control.getValue();
	var h_alpha  = hud_alpha.getValue();
	var h_offset = 0;
	var hvolts   = hud_volts.getValue();

	if (g == nil) { g = 0; }
	damp = (g * n) + (damp * (1 - n));

	pilot_g_damped.setDoubleValue(damp);

	# there should be an electrical param for hud, like other instruments,
	# so dealing here with power alimentation is a dirty workaround.
	if (hvolts > 24) {
		if (damp > 3) {
			if (damp > 5) {
				hud_alpha.setDoubleValue(h_offset);
			} else {
				h_offset = ((damp - 3) / 2 ) * h_intens;
				hud_alpha.setDoubleValue(h_intens - h_offset);
			}
		} else {
			hud_alpha.setDoubleValue(h_intens);
		}
	} else {
		hud_alpha.setDoubleValue(0);
	}
	# print(sprintf("pilot_g_damped in=%0.5f, out=%0.5f, h_offset=%0.5f", g, damp ,h_offset));

}
