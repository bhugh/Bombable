# Fairchild A-10 radio and navigation system
# Alexis BORY  < xiii at g2ms dot com >  -- Public Domain


# ILS: nav[0]
# -----------
var ils_freq         = props.globals.getNode("instrumentation/nav[0]/frequencies");
var ils_freq_sel     = ils_freq.getNode("selected-mhz", 1);
var ils_freq_sel_fmt = ils_freq.getNode("selected-mhz-fmt", 1);
var ils_btn          = props.globals.getNode("sim/model/A-10/A-10-nav/selector-ils");


# update selected-mhz with translated decimals
var nav0_freq_update = func {
	var test = getprop("instrumentation/nav[0]/frequencies/selected-mhz");
	if (! test) {
		setprop("sim/model/A-10/instrumentation/nav[0]/frequencies/freq-whole", 0);
	} else {
		setprop("sim/model/A-10/instrumentation/nav[0]/frequencies/freq-whole", test * 100);
	}
}


# TACAN: nav[1]
# ------------- 
var nav1_back = 0;

a10initprop="/sim/a10-TACAN-initialized";
var inited=getprop (a10initprop);
setprop(a10initprop,1);
if (!inited) { 
  setlistener( "instrumentation/tacan/switch-position", func {nav1_freq_update();} );
}  

var tc              = props.globals.getNode("instrumentation/tacan/");
var tc_sw_pos       = tc.getNode("switch-position");
var tc_freq         = tc.getNode("frequencies");
var tc_true_hdg     = props.globals.getNode("instrumentation/tacan/indicated-bearing-true-deg");
var tc_mag_hdg      = props.globals.getNode("sim/model/A-10/instrumentation/tacan/indicated-bearing-mag-deg");
var tcn_btn         = props.globals.getNode("instrumentation/tacan/switch-position");
var heading_offset  = props.globals.getNode("instrumentation/heading-indicator-fg/offset-deg");
var tcn_ident       = props.globals.getNode("instrumentation/tacan/ident");
var vtc_ident       = props.globals.getNode("instrumentation/nav[1]/nav-id");
var from_flag       = props.globals.getNode("sim/model/A-10/instrumentation/cdi/from-flag");
var to_flag         = props.globals.getNode("sim/model/A-10/instrumentation/cdi/to-flag");
var cdi_deflection  = props.globals.getNode("sim/model/A-10/instrumentation/cdi/needle-deflection");
var vtc_from_flag   = props.globals.getNode("instrumentation/nav[1]/from-flag");
var vtc_to_flag     = props.globals.getNode("instrumentation/nav[1]/to-flag");
var vtc_deflection  = props.globals.getNode("instrumentation/nav[1]/heading-needle-deflection");
var course_radial   = props.globals.getNode("instrumentation/nav[1]/radials/selected-deg");

var tacan_offset_apply = func {
	tcn            = tcn_btn.getValue();
	var hdg_offset = heading_offset.getValue();
	var true_hdg   = tc_true_hdg.getValue();
	if ( true_hdg and ( tcn == 1) ) {
		var new_mag_hdg = hdg_offset + true_hdg;
		tc_mag_hdg.setDoubleValue( geo.normdeg( new_mag_hdg ) );
	} else {
		tc_mag_hdg.setDoubleValue( 0 );
	}
}

var nav1_freq_update = func {
	if ( tc_sw_pos.getValue() == 1 ) {
		#print("nav1_freq_updat etc_sw_pos = 1");
		var tacan_freq = getprop( "instrumentation/tacan/frequencies/selected-mhz" );
		var nav1_freq = getprop( "instrumentation/nav[1]/frequencies/selected-mhz" );
		var nav1_back = nav1_freq;
		setprop("instrumentation/nav[1]/frequencies/selected-mhz", tacan_freq);
	} else {
	setprop("instrumentation/nav[1]/frequencies/selected-mhz", nav1_back);
	}
}

var tacan_XYtoggle = func {
	var xy_sign = tc_freq.getNode("selected-channel[4]");
	var s = xy_sign.getValue();
	if ( s == "X" ) {
		xy_sign.setValue( "Y" );
	} else {
		xy_sign.setValue( "X" );
	}
}

var tacan_tenth_adjust = func {
	var tenths = getprop( "instrumentation/tacan/frequencies/selected-channel[2]" );
	var hundreds = getprop( "instrumentation/tacan/frequencies/selected-channel[1]" );
	var value = (10 * tenths) + (100 * hundreds);
	var adjust = arg[0];
	var new_value = value + adjust;
	var new_hundreds = int(new_value/100);
	var new_tenths = (new_value - (new_hundreds*100))/10;
	setprop( "instrumentation/tacan/frequencies/selected-channel[1]", new_hundreds );
	setprop( "instrumentation/tacan/frequencies/selected-channel[2]", new_tenths );
}

# TACAN on HSI's Course Deviation Indicator
# -----------------------------------------------------
# CDI works with ils OR tacan OR vortac (which freq is tuned from the tacan panel)
var compas_card_dev_indicator = func {
	var tcn = tcn_btn.getValue();
	if ( tcn ) {
		var tcnid = tcn_ident.getValue();
		var vtcid = vtc_ident.getValue();
		if ( tcnid == vtcid ) {
			# we have a VORTAC
			from_flag.setBoolValue(vtc_from_flag.getBoolValue());
			to_flag.setBoolValue(vtc_to_flag.getBoolValue());
			cdi_deflection.setValue(vtc_deflection.getValue());
		} else {
			# we have a legacy TACAN
			var tcn_toflag = 1;
			var tcn_fromflag = 0;
			var tcn_bearing = tc_mag_hdg.getValue();
			var radial = course_radial.getValue();
			var delt = tcn_bearing - radial;
			if ( delt > 180 ) {
				delt -= 360;				
			} elsif ( delt < -180 ) {
				delt += 360;				
			}
			if ( delt > 90 ) {
				delt -= 180;
				tcn_toflag = 0;
				tcn_fromflag = 1;
			} elsif ( delt < - 90 ) {
				delt += 180;
				tcn_toflag = 0;
				tcn_fromflag = 1;
			}
			if ( delt > 10 ) { delt = 10 };
			if ( delt < -10 ) { delt = -10 };
			from_flag.setBoolValue(tcn_fromflag);
			to_flag.setBoolValue(tcn_toflag);
			cdi_deflection.setValue(delt);
		}
	}
}

# AN/ARC-186: VHF voice on comm[0] and homing on nav[2]
# -----------------------------------------------------

var nav2_selected_mhz = props.globals.getNode("instrumentation/nav[2]/frequencies/selected-mhz", 1);
var comm0_selected_mhz = props.globals.getNode("instrumentation/comm[0]/frequencies/selected-mhz", 1);
var vhf = props.globals.getNode("sim/model/A-10/instrumentation/vhf");
var vhf_mode = vhf.getNode("mode");
var vhf_selector = vhf.getNode("selector");
var vhf_load_state = vhf.getNode("load-state");
var vhf_preset = vhf.getNode("selected-preset");
var vhf_presets = vhf.getNode("presets");
var vhf_fqs = vhf.getNode("frequencies");
var vhf_fqs10 = vhf_fqs.getNode("alt-selected-mhz-x10");
var vhf_fqs1 = vhf_fqs.getNode("alt-selected-mhz-x1");
var vhf_fqs01 = vhf_fqs.getNode("alt-selected-mhz-x01");
var vhf_fqs0001 = vhf_fqs.getNode("alt-selected-mhz-x0001");

aircraft.data.add(vhf_preset);

# Displays nav[2] selected-mhz on the VHF radio set.
var alt_freq_update = func {
	var freq  = nav2_selected_mhz.getValue();
	if (freq == nil) { freq = 0; }	
	var freq10 = int(freq / 10);
	var freq1 = int(freq) - (freq10 * 10);
	var resr = rounding25((freq - int(freq)) * 1000);
	var freq01 = int(resr / 100);
	var freq0001 = ((resr / 100) - freq01) * 100;
	vhf_fqs10.setValue( freq10 );
	vhf_fqs1.setValue( freq1 );
	vhf_fqs01.setValue( freq01 );
	vhf_fqs0001.setValue( freq0001 );
}

var rounding25 = func(n) {
	var a = int( n / 25 );
	var l = ( a + 0.5 ) * 25;
	n = (n >= l) ? ((a + 1) * 25) : (a * 25);
	return( n );
}


# Updates comm[0] and nav[2] selected-mhz property from the VHF dialed freq
var alt_freq_to_freq = func {
	var freq10 = vhf_fqs10.getValue();
	var freq1 = vhf_fqs1.getValue();
	var freq01 = vhf_fqs01.getValue();
	var freq0001 = vhf_fqs0001.getValue();
	var freq = ( freq10 * 10 ) + freq1 + ( freq01 / 10 ) + ( freq0001 / 1000 );
	nav2_selected_mhz.setValue( freq );
	comm0_selected_mhz.setValue( freq );
}

# Changes the selected freq on comm[0] and nav[2]
var change_preset = func {
	var presets = vhf.getNode("presets");
	var p = vhf_preset.getValue();
	if ( p == nil ) { p = 1; }
	var new_p = p + arg[0];
	if (arg[0] == 1 and new_p == 21 ) {
		new_p = 1;
	} elsif (arg[0] == -1 and new_p == 0 ) {
		new_p = 20;
	}
	vhf_preset.setValue( new_p );
	var f_data = "preset[" ~ new_p ~ "]";
	p_freq = vhf_presets.getNode(f_data);
	var f = p_freq.getValue();
	if ( f == nil ) { f = 0; }
	nav2_selected_mhz.setValue( f );
	comm0_selected_mhz.setValue( f );
	alt_freq_update();
}

# Saves displayed freq in the pressets memory
# load_state used for the load button animation
var load_freq = func {
	var mode = vhf_mode.getValue();
	var selector = vhf_selector.getValue();
	if ( mode == 1 and selector == 3 ) {
		# mode to TR, selector to MAN
		var to_load_freq = nav2_selected_mhz.getValue();
		var p = vhf_preset.getValue();
		var f = "preset[" ~ p ~ "]";
		var p_freq = vhf_presets.getNode(f);
		p_freq.setValue(to_load_freq);
		vhf_load_state.setValue(1);
		settimer(func { vhf_load_state.setValue(0) }, 0.5);
	}
}

# Init ####################
var freq_startup = func {
	## nav[0] - ILS
	nav0_freq_update();
	aircraft.data.add(ils_freq_sel);
	aircraft.data.add(ils_freq_sel_fmt);
	## nav[1] - TACAN
	foreach (var f_tc; tc_freq.getChildren()) {
		aircraft.data.add(f_tc);
	}
	## comm[0] and nav[2] - VHF
	change_preset(0);
	# add all the restored pressets to a new aircraft data file
	foreach (var p_freq; vhf_presets.getChildren()) {
		aircraft.data.add(p_freq);
	}
	## HSI
	aircraft.data.add("instrumentation/heading-indicator-fg/offset-deg",
		"instrumentation/nav[1]/radials/selected-deg");
}

# Homing deviations computing loop
var ac_hdg = props.globals.getNode("/orientation/heading-deg", 1);
var st_hdg = props.globals.getNode("instrumentation/nav[2]/heading-deg", 1);
var vhf_hdev = vhf.getNode("homing-deviation",1);

var nav2_homing_devs = func {
	var ahdg = ac_hdg.getValue();
	var shdg = st_hdg.getValue();
	if ( shdg != nil ) {
		var d = shdg - ahdg;
		while ( d > 180) d -= 360;
		while ( d < -180) d += 360;
		vhf_hdev.setDoubleValue(d);
	}
}

# Other navigation panels
# -----------------------

# A-10-nav-mode-selector panel:
# buttons indices: HARS=0, VLOCS=1, TISL=2, NAV-CRS=3, MAN=4, ILS=5, TCN=6
var nav_mode_selector = func(n) {
	if ( n == 5 ) {
		var n_state = ils_btn.getBoolValue();
		ils_btn.setBoolValue(!n_state);
		tcn_btn.setBoolValue(0);
	} elsif ( n == 6) {
		var n_state = tcn_btn.getBoolValue();
		tcn_btn.setBoolValue(!n_state);
		ils_btn.setBoolValue(0);
	}
}
