#A6M2 electrical system.

var battery = nil;
var alternator = nil;

var last_time = 0.0;
var pwr_src = 0.0;

var bat_bus_volts = 0.0;
var emerg_bus_volts = 0.0;
var main_bus_volts = 0.0;
var ammeter_ave = 0.0;

BatteryClass = {};

BatteryClass.new = func {
    var obj = { parents : [BatteryClass],
            ideal_volts : 12.0,
            ideal_amps : 20.0,
            amp_hours : 12.75,
            charge_percent : 1.0,
            charge_amps : 7.0 };
    return obj;
}

AlternatorClass = {};

AlternatorClass.new = func {
    var obj = { parents : [AlternatorClass],
            rpm_source : "/engines/engine[0]/rpm",
            rpm_threshold : 500.0,
            ideal_volts : 14.0,
            ideal_amps : 20.0 };
    setprop( obj.rpm_source, 0.0 );
    return obj;
}

setlistener("/sim/signals/fdm-initialized", func {
    battery = BatteryClass.new();
    alternator = AlternatorClass.new();
    setprop("/controls/electric/battery-switch", 1.0);
    setprop("/controls/electric/external-power", 0);
    setprop("/controls/electric/engine[0]/generator", 1);
    setprop("/controls/switches/nav-lights", 1);
    print("Electrical  ---Check");
    update_electrical();
});

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
    var tmp = -(3.0 * x - 1.0);
    var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
    return me.ideal_volts * factor;
}

BatteryClass.get_output_amps = func {
    var x = 1.0 - me.charge_percent;
    var tmp = -(3.0 * x - 1.0);
    var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
    return me.ideal_amps * factor;
}



AlternatorClass.apply_load = func( amps, dt, src ) {
    var rpm = getprop(src);
    var factor = rpm / me.rpm_threshold;
    if ( factor > 1.0 ) {
        factor = 1.0;
    }
    var available_amps = me.ideal_amps * factor;
    return available_amps - amps;
}


AlternatorClass.get_output_volts = func( src ) {
    var rpm = getprop(src );
    var factor = rpm / me.rpm_threshold;
    if ( factor > 1.0 ) {
        factor = 1.0;
    }
    return me.ideal_volts * factor;
}


AlternatorClass.get_output_amps = func(src ){
    var rpm = getprop( src );
    var factor = rpm / me.rpm_threshold;
    if ( factor > 1.0 ) {
        factor = 1.0;
    }
    return me.ideal_amps * factor;
}

var update_electrical = func {
    var time = getprop("/sim/time/elapsed-sec");
    var dt = time - last_time;
    var last_time = time;
    update_virtual_bus( dt );
    settimer(update_electrical, 0);
}

var update_virtual_bus = func( dt ) {
    var battery_volts = battery.get_output_volts();
    var alternator_volts = alternator.get_output_volts("/engines/engine[0]/rpm");
    var external_volts = 0.0;
    var load = 0.0;

    var master_bat = getprop("/controls/electric/battery-switch");
    var master_alt = getprop("/controls/electric/engine[0]/generator");

    bat_bus_volts = 0.0;
    main_bus_volts = 0.0;
    var power_source = nil;

    if ( master_bat == 1.0 ) {
        bat_bus_volts = battery_volts;
        main_bus_volts = bat_bus_volts;
        emerg_bus_volts = bat_bus_volts;
        power_source = "battery";
    }else{
    if ( master_bat == 2.0 ) {
        emerg_bus_volts = battery_volts;
        power_source = "battery";
}}

    if ( master_alt and (alternator_volts > bat_bus_volts) ) {
        main_bus_volts = alternator_volts;
        bat_bus_volts = alternator_volts;
        power_source = "alternator";
    }

    if ( external_volts > bat_bus_volts ) {
        bat_bus_volts = external_volts;
        power_source = "external";
    }

    var starter_switch = getprop("/controls/engines/engine[0]/starter");
    var starter_volts = 0.0;
    if ( starter_switch ) {
        starter_volts = bat_bus_volts;
    }
    setprop("/systems/electrical/outputs/starter[0]", starter_volts);


    load += emergency_bus();
    load += Main_bus();

    var ammeter = 0.0;
    if ( bat_bus_volts > 1.0 ) {
        # normal load
        load += 15.0;

        # ammeter gauge
        if ( power_source == "battery" ) {
            ammeter = -load;
        } else {
            ammeter = battery.charge_amps;
        }
    }

    # charge/discharge the battery
    if ( power_source == "battery" ) {
        battery.apply_load( load, dt );
    } elsif ( bat_bus_volts > battery_volts ) {
        battery.apply_load( -battery.charge_amps, dt );
    }

    # filter ammeter needle pos
    ammeter_ave = 0.8 * ammeter_ave + 0.2 * ammeter;

    # outputs
    setprop("/systems/electrical/amps", ammeter_ave);
    setprop("/systems/electrical/volts", bat_bus_volts);
    setprop("/systems/electrical/amps", ammeter_ave);
    return load;
}

var emergency_bus = func() {
    var load = 0.0;
    setprop("/systems/electrical/outputs/nav[1]", emerg_bus_volts);
    setprop("/systems/electrical/outputs/com[0]", emerg_bus_volts);

    if ( getprop("/controls/switches/cabin-lights") ) {
        setprop("/systems/electrical/outputs/cabin-lights", emerg_bus_volts);
} else {
        setprop("/systems/electrical/outputs/cabin-lights", 0.0);
    }
    if ( getprop("/controls/switches/pitot-heat" ) ) {
        setprop("/systems/electrical/outputs/pitot-heat", emerg_bus_volts);
    } else {
        setprop("/systems/electrical/outputs/pitot-heat", 0.0);
    }
    return load;
}


var Main_bus = func() {
var load = 0.0;
setprop("/controls/hydraulic/system/engine-pump","false");
if(main_bus_volts > 0.2){
setprop("/controls/hydraulic/system/engine-pump","true");
}

setprop("/systems/electrical/outputs/instr-ignition-switch", main_bus_volts);

    if ( getprop("/controls/engines/engine[0]/fuel-pump") ) {
        setprop("/systems/electrical/outputs/fuel-pump", main_bus_volts);
    } else {
        setprop("/systems/electrical/outputs/fuel-pump", 0.0);
    }

    setprop("/systems/electrical/outputs/flaps",main_bus_volts);
    setprop("/systems/electrical/outputs/turn-coordinator",main_bus_volts);

    if ( getprop("/controls/switches/nav-lights" ) ) {
        setprop("/systems/electrical/outputs/nav-lights", main_bus_volts);
        if ( bat_bus_volts > 1.0 ) { load += 7.0; }
    } else {
        setprop("/systems/electrical/outputs/nav-lights", 0.0);
    }
    setprop("/systems/electrical/outputs/instrument-lights",main_bus_volts);

    if ( getprop("/controls/switches/strobe" ) ) {
        setprop("/systems/electrical/outputs/strobe-lights", main_bus_volts);
    } else {
        setprop("/systems/electrical/outputs/strobe-lights", 0.0);
    }

    if ( getprop("/controls/switches/taxi-lights" ) ) {
        setprop("/systems/electrical/outputs/taxi-lights", main_bus_volts);
    } else {
        setprop("/systems/electrical/outputs/taxi-lights", 0.0);
    }
    setprop("/systems/electrical/outputs/hsi", main_bus_volts);
    setprop("/systems/electrical/outputs/nav[0]",main_bus_volts);
    setprop("/systems/electrical/outputs/dme", main_bus_volts);
    setprop("/systems/electrical/outputs/transponder", main_bus_volts);
    setprop("/systems/electrical/outputs/adf", main_bus_volts);

    return load;
}
