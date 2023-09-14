#A-10 electrical system.
    # A-10 external-battery-switch assumed always on
    # A-10 external pwr assumed never connected


var battery = nil;
var alternator = nil;

var last_time = 0.0;

var bat_src_volts = 0.0;
var external_volts    = 0.0;
var battery_bus_volts   = 0.0;
var L_DC_bus_volts      = 0.0;
var R_DC_bus_volts      = 0.0;
var L_AC_bus_volts      = 0.0;
var R_AC_bus_volts      = 0.0;
var L_conv_volts        = 0.0;
var R_conv_volts        = 0.0;
var AC_ESSEN_bus_volts  = 0.0;
var DC_ESSEN_bus_volts  = 0.0;
var ammeter_ave = 0.0;


var APU_Running   = props.globals.getNode("sim/model/A-10/systems/apu/running");
var APU_Rpm       = props.globals.getNode("sim/model/A-10/systems/apu/rpm-norm");

var init_electrical = func {
    battery = BatteryClass.new();
    alternator = AlternatorClass.new();
    setprop("controls/switches/master-avionics", 0);
    setprop("controls/electric/battery-switch", 0);
    setprop("controls/electric/external-power", 0);
    setprop("controls/electric/engine[0]/generator", 0);
    setprop("controls/electric/engine[1]/generator", 0);
    setprop("sim/model/A-10/controls/switches/inverter", 1);
    setprop("systems/electrical/power_source", "none");
    setprop("systems/electrical/L-conv-volts", 0.0);
    setprop("systems/electrical/R-conv-volts", 0.0);
    setprop("systems/electrical/inverter-volts", 0.0);
    setprop("systems/electrical/radar", 24.0);
    # radar only used to allow Air to Air Refueling code to work.
}





var BatteryClass = {};
BatteryClass.new = func {
    var obj = { parents : [BatteryClass],
            ideal_volts : 26.0,
            ideal_amps : 30.0,
            amp_hours : 12.75,
            charge_percent : 1.0,
            charge_amps : 7.0 };
    return obj;
}
BatteryClass.apply_load = func( amps, dt ) {
    var amphrs_used = amps * dt / 3600.0;
    var percent_used = amphrs_used / me.amp_hours;
    me.charge_percent -= percent_used;
    if ( me.charge_percent < 0.0 ) {
        me.charge_percent = 0.0;
    } elsif ( me.charge_percent > 1.0 ) {
        me.charge_percent = 1.0;
    }
    return me.amp_hours * me.charge_percent;
}
BatteryClass.get_output_volts = func {
    var x = 1.0 - me.charge_percent;
    var factor = x / 10;
    return me.ideal_volts - factor;
}
BatteryClass.get_output_amps = func {
    var x = 1.0 - me.charge_percent;
    var tmp = -(3.0 * x - 1.0);
    var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
    return me.ideal_amps * factor;
}

var AlternatorClass = {};
AlternatorClass.new = func {
    var obj = { parents : [AlternatorClass],
            ideal_volts : 26.0,
            ideal_amps : 60.0 };
    return obj;
}
AlternatorClass.apply_load = func( amps, dt, src ) {
    var rpm = getprop(src);
    var factor = 0;
    # A-10 APU can have 0 rpm
    if (rpm > 0) {
        factor = math.ln(rpm)/4;
    }
    var available_amps = me.ideal_amps * factor;
    return available_amps - amps;
}
AlternatorClass.get_output_volts = func( src ) {
    var rpm = getprop(src);
    var factor = 0;
    # A-10 APU can have 0 rpm
    if (rpm > 0) {
        factor = math.ln(rpm)/4;
    }
    return me.ideal_volts * factor;
}
AlternatorClass.get_output_amps = func(src ){
    rpm = getprop(src);
    var factor = 0;
    # A-10 APU can have 0 rpm
    if (rpm > 0) {
        factor = math.ln(rpm)/4;
    }
    return me.ideal_amps * factor;
}



var update_electrical = func {
    var time = getprop("sim/time/elapsed-sec");
    var dt = time - last_time;
    last_time = time;
    update_virtual_bus( dt );
    check_bleed_air();
}




var update_virtual_bus = func( dt ) {
    var eng_outof         = getprop("engines/engine[0]/out-of-fuel");
    var eng_outof1        = getprop("engines/engine[1]/out-of-fuel");
    var master_bat        = getprop("controls/electric/battery-switch");
    var master_apu        = getprop("controls/APU/generator");
    var master_alt        = getprop("controls/electric/engine[0]/generator");
    var master_alt1       = getprop("controls/electric/engine[1]/generator");
    var master_inv        = getprop("sim/model/A-10/controls/switches/inverter");
    var L_gen_volts       = 0.0;
    var R_gen_volts       = 0.0;
    var APU_gen_volts     = 0.0;
    #var INV_volts         = getprop("systems/electrical/inverter-volts");
    var INV_volts         = 0.0;

    battery_volts         = battery.get_output_volts();
    L_AC_bus_volts        = 0.0;
    R_AC_bus_volts        = 0.0;
    load                  = 0.0;
    AC_ESSEN_bus_volts    = 0.0;
    R_conv_volts          = 0.0;
    L_conv_volts          = 0.0;
    var power_source      = nil;
    #var ammeter           = 0.0;

    if (master_alt and !eng_outof) {
        L_gen_volts = alternator.get_output_volts("sim/model/A-10/engines/engine[0]/n2");
    }
    if (master_alt1 and !eng_outof1) {
        R_gen_volts = alternator.get_output_volts("sim/model/A-10/engines/engine[1]/n2");
    }
    if(master_apu and getprop("controls/APU/generator-serviceable")) {
        APU_gen_volts = alternator.get_output_volts("sim/model/A-10/systems/apu/rpm-norm");
    }

    # determine power source
    if ( master_bat == 1 ) { bat_src_volts = battery_volts; }
    if (APU_gen_volts >= 23) {
        R_conv_volts = APU_gen_volts;
        if ((L_gen_volts < 23) and (R_gen_volts < 23)) {
            L_AC_bus_volts = APU_gen_volts;
            R_AC_bus_volts = APU_gen_volts;
            AC_ESSEN_bus_volts = APU_gen_volts;
            L_conv_volts = APU_gen_volts;
            power_source = "apu";
        }
        if ((L_gen_volts < 23) and (R_gen_volts >= 23)) {
            L_AC_bus_volts = R_gen_volts;
            R_AC_bus_volts = R_gen_volts;
            AC_ESSEN_bus_volts = R_gen_volts;
            L_conv_volts = R_gen_volts;
        }
        if ((L_gen_volts >= 23) and (R_gen_volts < 23)) {
            L_AC_bus_volts = L_gen_volts;
            R_AC_bus_volts = L_gen_volts;
            AC_ESSEN_bus_volts = L_gen_volts;
            L_conv_volts = L_gen_volts;
        }
        if ((L_gen_volts >= 23) and (R_gen_volts >= 23)) {
            L_AC_bus_volts = L_gen_volts;
            R_AC_bus_volts = R_gen_volts;
            AC_ESSEN_bus_volts = L_gen_volts;
            L_conv_volts = L_gen_volts;
        }
    }
    if (APU_gen_volts < 23) {
        if ((L_gen_volts < 23) and (R_gen_volts < 23)) {
            L_AC_bus_volts = 0.0;
            R_AC_bus_volts = 0.0;
            AC_ESSEN_bus_volts = INV_volts;
            L_conv_volts = 0.0;
            R_conv_volts = 0.0;
        }
        if ((L_gen_volts < 23) and (R_gen_volts >= 23)) {
            L_AC_bus_volts = R_gen_volts;
            R_AC_bus_volts = R_gen_volts;
            AC_ESSEN_bus_volts = R_gen_volts;
            L_conv_volts = R_gen_volts;
            R_conv_volts = R_gen_volts;
        }
        if ((L_gen_volts >= 23) and (R_gen_volts < 23)) {
            L_AC_bus_volts = L_gen_volts;
            R_AC_bus_volts = L_gen_volts;
            AC_ESSEN_bus_volts = L_gen_volts;
            L_conv_volts = L_gen_volts;
            R_conv_volts = L_gen_volts;
        }
        if ((L_gen_volts >= 23) and (R_gen_volts >= 23)) {
            L_AC_bus_volts = L_gen_volts;
            R_AC_bus_volts = R_gen_volts;
            AC_ESSEN_bus_volts = L_gen_volts;
            L_conv_volts = L_gen_volts;
            R_conv_volts = L_gen_volts;
        }
    }

    if ((L_conv_volts >= 23) and (R_conv_volts >= 23)) {
        DC_ESSEN_bus_volts      = L_conv_volts;
        AUX_DC_ESSEN_bus_volts  = L_conv_volts;
        battery_bus_volts       = L_conv_volts;
        L_DC_bus_volts          = L_conv_volts;
        R_DC_bus_volts          = R_conv_volts;
        bat_src_volts           = L_conv_volts;
        power_source = "none";
    }
    if ((L_conv_volts < 23) and (R_conv_volts >= 23)) {
        DC_ESSEN_bus_volts      = R_conv_volts;
        AUX_DC_ESSEN_bus_volts  = R_conv_volts;
        battery_bus_volts       = R_conv_volts;
        L_DC_bus_volts          = R_conv_volts;
        R_DC_bus_volts          = R_conv_volts;
        bat_src_volts           = R_conv_volts;
        power_source = "none";
    }
    if ((L_conv_volts >= 23) and (R_conv_volts < 23)) {
        DC_ESSEN_bus_volts      = L_conv_volts;
        AUX_DC_ESSEN_bus_volts  = L_conv_volts;
        battery_bus_volts       = L_conv_volts;
        L_DC_bus_volts          = L_conv_volts;
        R_DC_bus_volts          = L_conv_volts;
        bat_src_volts           = L_conv_volts;
        power_source = "none";
    }
    if ((L_conv_volts < 23) and (R_conv_volts < 23)) {
        DC_ESSEN_bus_volts      = bat_src_volts;
        AUX_DC_ESSEN_bus_volts  = bat_src_volts;
        battery_bus_volts       = bat_src_volts;
        L_DC_bus_volts          = 0.0;
        R_DC_bus_volts          = 0.0;
        power_source = "battery";
    }
    if (( master_bat == 0 ) and (L_conv_volts < 23) and (L_conv_volts < 23)) {
        DC_ESSEN_bus_volts      = 0.0;
        AUX_DC_ESSEN_bus_volts  = 0.0;
    }
    # Inverter
    if (( master_inv == 2 ) and (L_gen_volts < 20) and (R_gen_volts < 20)) {
        INV_volts = bat_src_volts;
        power_source = "battery"; 		# Does not mean that the battery is
                                        # connected to any bus.
    } elsif ( master_inv == 1 ) {
        INV_volts = 0.0;
    } elsif ( master_inv == 0 ) {
        INV_volts = bat_src_volts;
        power_source = "battery";
    }




    load += BATT_bus();
    load += DC_ESSEN_bus();
    load += AUX_DC_ESSEN_bus();
    load += L_DC_bus();
    load += R_DC_bus();
    load += L_AC_bus();
    load += R_AC_bus();
    load += AC_ESSEN_bus();
    if ( bat_src_volts > 1.0 ) {
        # normal load
        load += 15.0;
        # ammeter gauge
        #if ( power_source == "battery" ) {
        #    ammeter = -load;
        #} else {
        #    ammeter = battery.charge_amps;
        #}
    }
    # charge/discharge the battery
    if ( power_source == "battery" ) {
        battery.apply_load( load, dt );
        #setprop( "systems/electrical/power_source", power_source );
    } elsif ( bat_src_volts > battery_volts ) {
        battery.apply_load( -battery.charge_amps, dt );
    }
    setprop("systems/electrical/power_source", power_source);
    # filter ammeter needle pos
    #ammeter_ave = 0.8 * ammeter_ave + 0.2 * ammeter;
    # outputs
    setprop("systems/electrical/amps", ammeter_ave);
    setprop("systems/electrical/volts", bat_src_volts);
    #setprop("systems/electrical/ac_amps", AC_bus_amps);
    setprop("systems/electrical/inverter-volts", INV_volts);
    setprop("systems/electrical/APU-gen-volts", APU_gen_volts);
    setprop("systems/electrical/L-AC-volts", L_AC_bus_volts);
    setprop("systems/electrical/R-AC-volts", R_AC_bus_volts);
    setprop("systems/electrical/L-conv-volts", L_conv_volts);
    setprop("systems/electrical/R-conv-volts", R_conv_volts);
    return load;
}




var BATT_bus = func() {
    load = 0.0;
    if ( getprop("controls/switches/cabin-lights") ) {
        setprop("systems/electrical/outputs/cabin-lights", battery_bus_volts);
    } else {
        setprop("systems/electrical/outputs/cabin-lights", 0.0);
    }
    return load;
}

var DC_ESSEN_bus = func() {
	load = 0.0;
	var DC_ESSEN_ok = 0;
	setprop("systems/electrical/outputs/nav[0]", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/com[0]", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/nav[1]", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/com[1]", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/nav[2]", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/ldg-warning-system", DC_ESSEN_bus_volts);
	#setprop("systems/electrical/outputs/apu-start-system", DC_ESSEN_bus_volts);
	setprop("systems/electrical/outputs/caution-panel", DC_ESSEN_bus_volts);

	if ( DC_ESSEN_bus_volts >= 20) {
		DC_ESSEN_ok = 1;
	}

	load += A10fuel.DC_boost_pump.getBoolValue() * 15;
		
	
	# APU starter
	if ( APU_Rpm.getValue() < 60 and APU_Running.getBoolValue() ) {
		load += 120.0;
	}


	# Cross Feed switch
	if ( getprop("sim/model/A-10/controls/fuel/cross-feed-sw") and DC_ESSEN_ok ) {
		setprop("systems/A-10-fuel/cross-feed-valve", 1);
		load += 0.2;
	} else {
		setprop("systems/A-10-fuel/cross-feed-valve", 0);
	}

	# Tank Gate switch
	if ( getprop("sim/model/A-10/controls/fuel/tk-gate-switch") and DC_ESSEN_ok ) {
		setprop("systems/A-10-fuel/tank-gate-valve", 1);
		load += 0.2;
	} else {
		setprop("systems/A-10-fuel/tank-gate-valve", 0)
	}

	# external tank pumps to feed internal tanks
	var int_tanks_filled = 0;
	for( var i = 0; i < 4; i += 1 ) {
		if ( getprop("consumables/fuel/tank["~i~"]/fill-valve") ) {
			int_tanks_filled += 1;
		}
	}

	# external wing tanks
	if (
		int_tanks_filled > 0
		and getprop("controls/fuel/tank[4]/boost-pump[0]")
		and !getprop("systems/refuel/receiver-lever")
		and getprop("controls/fuel/tank[4]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[4]/level-gal_us") > 1.56
		and getprop("systems/bleed-air/psi") > 7
		and DC_ESSEN_ok
	) {
		A10fuel.Left_External.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Left_External.set_boost_pump(0);
	}

	# note: right external wing pump is controlled by controls/fuel/tank[4]/boost-pump[0] too
	if (
		int_tanks_filled > 0
		and getprop("controls/fuel/tank[4]/boost-pump[0]")
		and !getprop("systems/refuel/receiver-lever")
		and getprop("controls/fuel/tank[6]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[6]/level-gal_us") > 1.56
		and getprop("systems/bleed-air/psi") > 7
		and DC_ESSEN_ok
	) {
		A10fuel.Right_External.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Right_External.set_boost_pump(0);
	}

	# external fuselage tank
	if (
		int_tanks_filled > 0
		and getprop("controls/fuel/tank[5]/boost-pump[0]")
		and !getprop("systems/refuel/receiver-lever")
		and getprop("controls/fuel/tank[5]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[5]/level-gal_us") > 1.56
		and ! A10fuel.Left_External.get_boost_pump()
		and ! A10fuel.Right_External.get_boost_pump()
		and getprop("systems/bleed-air/psi") > 7
		and DC_ESSEN_ok
	) {
		A10fuel.Fuse_External.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Fuse_External.set_boost_pump(0);
	}

	# Left and right gravity valve.
	if (
		getprop("consumables/fuel/tank[1]/level-gal_us") < 93.75
		and getprop("consumables/fuel/tank[0]/level-gal_us") > 2.34
		and ! A10fuel.Left_Wing.get_boost_pump()
		and DC_ESSEN_ok
	) {
		A10fuel.Left_Wing.set_transfering(1);
		load += 0.2;
	} else {
		A10fuel.Left_Wing.set_transfering(0);
	}

	if (
		getprop("consumables/fuel/tank[2]/level-gal_us") < 93.75
		and getprop("consumables/fuel/tank[3]/level-gal_us") > 2.34
		and ! A10fuel.Right_Wing.get_boost_pump()
		and DC_ESSEN_ok
	) {
		A10fuel.Right_Wing.set_transfering(1);
		load += 0.2;
	} else {
		A10fuel.Right_Wing.set_transfering(0)
	}

	return load;
}


var AUX_DC_ESSEN_bus = func() {
	load = 0.0;
	setprop("systems/electrical/outputs/engines-ignitors", AC_ESSEN_bus_volts);
	return load;
}

var L_DC_bus = func() {
	load = 0.0;
	setprop("systems/electrical/outputs/rwr", L_DC_bus_volts);
	foreach (var t; A10fuel.Tank.list) { load += t.get_fill_valve() * 0.2 }
	return load;
}

var R_DC_bus = func() {
    load = 0.0;
    setprop("systems/electrical/outputs/uhf-adf", R_DC_bus_volts);
    setprop("systems/electrical/outputs/vhf-comm", R_DC_bus_volts);
    setprop("systems/electrical/outputs/vhf-fm", R_DC_bus_volts);
    setprop("systems/electrical/outputs/ils", R_DC_bus_volts);
    setprop("systems/electrical/outputs/gau-8", R_DC_bus_volts);
    return load;
}

var L_AC_bus = func() {
	load = 0.0;

	# Left wing and main fuel pumps power
	if (
		getprop("controls/fuel/tank[0]/boost-pump[0]")
		and getprop("controls/fuel/tank[0]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[0]/level-gal_us") > 1.56
		and L_AC_bus_volts >= 20
	) {
		A10fuel.Left_Wing.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Left_Wing.set_boost_pump(0);
	}

	if (
		getprop("controls/fuel/tank[1]/boost-pump[0]")
		and getprop("controls/fuel/tank[1]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[1]/level-gal_us") > 1.56
		and L_AC_bus_volts >= 20
		and ! A10fuel.Left_Wing.get_boost_pump()
	) {
		A10fuel.Left_Main.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Left_Main.set_boost_pump(0);
	}
	return load;
}

var R_AC_bus = func() {
	load = 0.0;
	setprop("systems/electrical/outputs/tacan", R_AC_bus_volts);
	setprop("systems/electrical/outputs/hsi", R_AC_bus_volts);
	setprop("systems/electrical/outputs/adi", R_AC_bus_volts);
	setprop("systems/electrical/outputs/cadc", R_AC_bus_volts);
	setprop("systems/electrical/outputs/nav-mode", R_AC_bus_volts);
	setprop("systems/electrical/outputs/aoa-indexer", R_AC_bus_volts);
	var hud_mode = getprop("sim/model/A-10/controls/hud/mode-selector");
	if (hud_mode > 0) {
		setprop("systems/electrical/outputs/hud", R_AC_bus_volts);
	} else {
		setprop("systems/electrical/outputs/hud", 0);
	}
	setprop("instrumentation/attitude-indicator/spin", R_AC_bus_volts/30);
	setprop("instrumentation/turn-indicator/spin", R_AC_bus_volts/30);
	setprop("systems/electrical/outputs/DG", R_AC_bus_volts);

	# Right wing and main fuel pumps power
	if (
		getprop("controls/fuel/tank[3]/boost-pump[0]")
		and getprop("controls/fuel/tank[3]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[3]/level-gal_us") > 1.56
		and R_AC_bus_volts >= 20
	) {
		A10fuel.Right_Wing.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Right_Wing.set_boost_pump(0);
	}

	if (
		getprop("controls/fuel/tank[2]/boost-pump[0]")
		and getprop("controls/fuel/tank[2]/boost-pump-serviceable")
		and getprop("consumables/fuel/tank[2]/level-gal_us") > 1.56
		and R_AC_bus_volts >= 20
		and ! A10fuel.Right_Wing.get_boost_pump()
	) {
		A10fuel.Right_Main.set_boost_pump(1);
		load += 15.0;
	} else {
		A10fuel.Right_Main.set_boost_pump(0);
	}
	return load;
}

var AC_ESSEN_bus = func() {
	load = 0.0;
	setprop("systems/electrical/outputs/fuel-gauge-sel", AC_ESSEN_bus_volts);

	for(var i=0; i<2; i+=1) {
		for(var j=0; j<2; j+=1) {
			if(getprop("controls/engines/engine["~i~"]/engines-ignitors["~j~"]")) {
				setprop("systems/electrical/outputs/engine["~i~"]/engines-ignitors["~j~"]", AC_ESSEN_bus_volts);
				load += 25.0;
			} else {
				setprop("systems/electrical/outputs/engine["~i~"]/engines-ignitors["~j~"]", 0);
			}
		}
	}
	return load;
}



# bleed air system
# ----------------
var check_bleed_air= func {
	# max ECS incomming pressure : 65 psi ( from Environment Control System valve)
	# nin rpm from a running TF34 engine to start the other one : 85 %rpm
	# All numbers below guessed from above
	# min pressure for TF34 engine start : 50 psi
	# nominal APU : 70 psi @ 100 %rpm @ standard day (pressure = 29.92inhg)
	# nominal TF34 : 60 psi @ 90 %rpm
	var p0 = getprop("sim/model/A-10/engines/engine[0]/n2") * 0.67;
	var p1 = getprop("sim/model/A-10/engines/engine[1]/n2") * 0.67;
	# APU provide bleed air psi > 50 psi up to an altitude of 10'000 ft @ standard day and 100% RPM
	var p2 = (getprop("environment/pressure-inhg")*2.13538+6.1093)*(getprop("sim/model/A-10/systems/apu/rpm-norm")/100);
	var bleed_air = p0;
	if(p1 > bleed_air) { bleed_air = p1; }
	if(p2 > bleed_air) { bleed_air = p2; }
	setprop("systems/bleed-air/psi", bleed_air);
	# TODO: add bleed air temperature to monitor in warn panel BLEED AIR LEAK (warn light on if temp > 400°F => 204°C)
}


# other electrical power controls
# -------------------------------
var inverter_switch = func {
    var inv_pos = props.globals.getNode("sim/model/A-10/controls/switches/inverter", 1);
    var pos = inv_pos.getValue();
    var input = arg[0];
    if ( input == 1 ) {
        if ( pos == 0 ) {
            inv_pos.setIntValue(1);
        } elsif ( pos == 1 ) {
            inv_pos.setIntValue(2);
        }
    } else {
        if ( pos == 2 ) {
            inv_pos.setIntValue(1);
        } elsif ( pos == 1 ) {
            inv_pos.setIntValue(0);
        }
    }
}




# lighting controls
# -----------------

var nav_lights_switcher = func {
    var flash = props.globals.getNode("sim/model/A-10/controls/lighting/nav-lights-flash", 1);
    var s_pos = props.globals.getNode("sim/model/A-10/controls/lighting/nav-lights-switch", 1);
    var pos = s_pos.getValue();
    var input = arg[0];
    if ( input == 1 ) {
        if ( pos == 0 ) {
            s_pos.setIntValue(1);
        } elsif ( pos == 1 ) {
            s_pos.setIntValue(2);
            flash.setBoolValue(1);
        }
    } else {
        if ( pos == 2 ) {
            s_pos.setIntValue(1);
            flash.setBoolValue(0);
        } elsif ( pos == 1 ) {
            s_pos.setIntValue(0);
        }
    }
}



var land_lights_switcher = func {
    var s_pos = props.globals.getNode("sim/model/A-10/controls/lighting/land-lights-switch", 1);
    var pos = s_pos.getValue();
    var input = arg[0];
    if ( input == 1 ) {
        if ( pos == 0 ) {
            s_pos.setIntValue(1);
        } elsif ( pos == 1 ) {
            s_pos.setIntValue(2);
        }
    } else {
        if ( pos == 2 ) {
            s_pos.setIntValue(1);
        } elsif ( pos == 1 ) {
            s_pos.setIntValue(0);
        }
    }
}
