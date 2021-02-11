# Simple vibrating yawstring

var elapsed_time = 0;

var yawstring = func {

	var airspeed = getprop("velocities/airspeed-kt");
	var position = getprop("orientation/side-slip-deg");
	var dt = getprop("sim/time/delta-sec");

	var severity = -(airspeed / 20) + 2 * (airspeed / 20) * rand();
	var noise = -5 + 10 * rand();

	elapsed_time += dt;


	# we derive a sine based factor to give us smoothly
	# varying value between -1 and 1
	var factor  = math.sin(globals.D2R * (elapsed_time * 100 * airspeed/10));
	var h_angle = 10 * factor;

	#30% variation of airspeed
	var airstring = 0.70 * airspeed + 0.30 * airspeed * rand();


	if (airspeed >= 20 ){
		setprop("instrumentation/yawstring", position );
		setprop("instrumentation/yawstring-flutter", severity + noise);
	} else {
		setprop("instrumentation/yawstring", position);
		setprop("instrumentation/yawstring-flutter", h_angle + noise);
	}

	setprop("instrumentation/airstring", airstring);

	settimer(yawstring, 0);

}

# Start the yawstring ASAP
yawstring();
