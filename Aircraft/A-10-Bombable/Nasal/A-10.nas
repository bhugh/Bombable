var UPDATE_PERIOD = 0.1;
var ikts        = props.globals.getNode("velocities/airspeed-kt");
var audio_alt_warn_signal = props.globals.getNode("sim/model/A-10/instrumentation/warnings/audio-alt");


# Flaps ###################
# automatic retraction of the flaps if speed exceed 210 KIAS
# flap will automatically reextended if speed is reduced to 190
# KIAS and flap lever is on MVR or DN.
var speed_toggle_flap = func {
	var kias_speed = getprop("instrumentation/airspeed-indicator/indicated-speed-kt");
	var curr_set = getprop("sim/flaps/current-setting");
	if(kias_speed > 210) {
		setprop("controls/flight/flaps", 0.0);
	} elsif((kias_speed < 190) and (curr_set != nil)) {
		setprop("controls/flight/flaps", getprop("sim/flaps/setting["~curr_set~"]"));
	}
}


# A-10 dialogs
var A10_dlg_syst_fail = gui.Dialog.new("dialog","Aircraft/A-10-Bombable/Dialogs/system-failures.xml");

# SAS #####################
# Stability Augmentation System.
# - Smooths the elevator input.
# - Damps the elevator output when positive ie: diving. (max output = 0.47)
var pitch_sas_sw  = props.globals.getNode("sim/model/A-10/controls/sas/pitch-sas-switch");
var raw_elev      = props.globals.getNode("controls/flight/elevator");
var sas_elev      = props.globals.getNode("sim/model/A-10/controls/flight/sas-elevator");
var sas_low_aoa_avoid = props.globals.getNode("sim/model/A-10/controls/flight/sas-low-aoa", 1);
var last_sas_elev = 0;
var sas_elev_smooth_factor = 0.1;
var aoa           = props.globals.getNode("orientation/alpha-deg");

var sas = func {
	var p_sas_sw = pitch_sas_sw.getBoolValue();
	var raw_e = raw_elev.getValue();
	var low_aoa_avoid = 0;
	if (p_sas_sw) {
		var filtered_move = (raw_e - last_sas_elev) * sas_elev_smooth_factor;
		var new_sas_elev = last_sas_elev + filtered_move;
		last_sas_elev = new_sas_elev;
		if (new_sas_elev > -0.01) {
			var curr_aoa = aoa.getValue();
			var curr_kias = ikts.getValue();
			if ( curr_aoa < 2 and curr_kias > 180 ) {
				curr_aoa -= 2;
				low_aoa_avoid = curr_aoa * (0.03 - (0.06 * curr_aoa));
				if (low_aoa_avoid < -0.13 ){ low_aoa_avoid = -0.13}
			}
			new_sas_elev = (new_sas_elev * (0.95 - (0.48 * new_sas_elev))) + low_aoa_avoid;
		} 
		sas_elev.setDoubleValue(new_sas_elev);
	} else {
		sas_elev.setDoubleValue(raw_e);
	}
	sas_low_aoa_avoid.setDoubleValue(low_aoa_avoid);
}

# Audio Altitude Warning ##
var audio_alt_vol = props.globals.getNode("sim/model/A-10/instrumentation/warnings/audio-alt-volume");
aircraft.data.add(audio_alt_vol);

var audio_alt_warn_counter = 0;
var audio_alt_warning = func {
	var gear = getprop("gear/gear[0]/position-norm");
	var alt = getprop("position/altitude-agl-ft");
	if ( audio_alt_warn_counter == 0 and gear == 0 and alt < 200 ) {
		audio_alt_warn_signal.setBoolValue(1);
	}
	audio_alt_warn_counter += 1;
	if ( audio_alt_warn_counter == 20 or alt >= 200 ) {
		audio_alt_warn_counter = 0;
		audio_alt_warn_signal.setBoolValue(0);
	}
	setprop("sim/model/A-10/instrumentation/warnings/alt_warn_counter", audio_alt_warn_counter);
}

# Accelerometer ###########
var g_curr 	  	= props.globals.getNode("accelerations/pilot-g");
var g_max	   	= props.globals.getNode("sim/model/A-10/instrumentation/g-meter/g-max");
var g_min	   	= props.globals.getNode("sim/model/A-10/instrumentation/g-meter/g-min");
aircraft.data.add( g_min, g_max );

var g_min_max = func {
	# records g min and max values
	var curr = g_curr.getValue();
	var max = g_max.getValue();
	var min = g_min.getValue();
	if ( curr >= max ) {
		g_max.setDoubleValue(curr);
	} elsif ( curr <= min ) {
		g_min.setDoubleValue(curr);
	}
}

# Main loop ###############
var cnt = 0;	# elecrical is done each 0.3 sec.
				# hud is done each 0.1 sec.
				# fuel is done each 0.1 sec.
				# flaps is done each 0.6 sec.

var main_loop = func {
	cnt += 1;
	sas();
	A10hud.update_loop();
	apu.update_loop();
	A10fuel.update_loop();
	A10engines.update_loop(0);
	A10engines.update_loop(1);
	nav_scripts.nav2_homing_devs();
	nav_scripts.tacan_offset_apply();
	nav_scripts.compas_card_dev_indicator();
	g_min_max();
	if ((cnt == 3 ) or (cnt == 6 )) {
		audio_alt_warning();
		electrical.update_electrical();
		if (cnt == 6 ) {
			speed_toggle_flap();
			cnt = 0;
		}
	}
	settimer(main_loop, UPDATE_PERIOD);
}



# Trajectory markers ######
var toggle_traj_mkr = func {
	var p = "/ai/submodels/trajectory-markers";
	setprop(p, !getprop(p));
}



# Init ####################
var init = func {
  #bhugh - 2011-09
  #added this to stop repeated reinitializations of the same timer loops
  #The 'real' way to do this is to inc a loop timer whenever a timer loop is re-inited,
  #and then kill off all loops but the current one.  And kill all listeners before
  #starting any new ones to do the same thing. 
  #
  #But this quick & dirty solution should help a lot.
  #It just keeps track of whether the A-10 has been initialized already and if
  # it does it refrains from re-starting loops and re-setting listeners again
  # (which results in duplicate loops and duplicate listeners, and massively
  # slows down FG when the A-10 has been re-started or re-initialized a few times)
  #
  
  a10initprop="/sim/a10-initialized";
  var inited=getprop (a10initprop);
  setprop(a10initprop,1);
  if (inited) var msg=" - warm reboot"; 
  else var msg=" - cold start";
  print ("Initializing A-10", msg);
  
  if (! inited) {
  	settimer(A10autopilot.ap_common_aileron_monitor, 0.5);
  	settimer(A10autopilot.ap_common_elevator_monitor, 0.5);
  	settimer(A10autopilot.altimeter_monitor, 0.5);
  	#print("Initializing A-10 CCIP range calculator");
  }
  	
	print("Initializing Electrical System");
	electrical.init_electrical();
	
  print("Initializing Engines");
	A10engines.initialize();
	
  print("Initializing Fuel System");
	A10fuel.init();
	
	
	if (! inited) {
    print("Initializing Weapons System.");
    A10weapons.initialize();
  } else {
  	#bhugh, 2011-09, this updates our weapons buttons and sets them so they can be released, 
    #based on the pre-loaded/default weapons config in the -set.xml file
	  A10weapons.update_stations();

  }  
	
  nav_scripts.freq_startup();
	
	
  if (! inited) settimer(func {canopy.cockpit_state()}, 3);
	aircraft.data.save();
	if (! inited) settimer(main_loop, 0.5);
}
setlistener("/sim/signals/fdm-initialized", init);


# Lighting ################
# strobes
var strobe_switch = props.globals.getNode("controls/lighting/strobe", 1);
aircraft.light.new("sim/model/A-10/lighting/strobe", [0.05, 1.00], strobe_switch);

# nav lights
var nav_lights_switch = props.globals.getNode("sim/model/A-10/controls/lighting/nav-lights-flash", 1);
aircraft.light.new("sim/model/A-10/lighting/nav-lights", [0.62, 0.62], nav_lights_switch);

# warning lights medium speed
var warn_medium_lights_switch = props.globals.getNode("sim/model/A-10/controls/lighting/warn-medium-lights-switch", 1);
aircraft.light.new("sim/model/A-10/lighting/warn-medium-lights", [0.40, 0.30], warn_medium_lights_switch);

# warning lights low speed
var warn_slow_lights_switch = props.globals.getNode("sim/model/A-10/controls/lighting/warn-slow-lights-switch", 1);
aircraft.light.new("sim/model/A-10/lighting/warn-slow-lights", [0.12, 1.5], warn_slow_lights_switch);
warn_slow_lights_switch.setBoolValue(1);
