# This is aminor amendment of fuel.nas which changes the logic so that the 
# code no longer changes the selection state of tanks.



# Properties under /consumables/fuel/tank[n]:
# + level-gal_us    - Current fuel load.  Can be set by user code.
# + level-lbs       - OUTPUT ONLY property, do not try to set
# + selected        - boolean indicating tank selection.
# + density-ppg     - Fuel density, in lbs/gallon.
# + capacity-gal_us - Tank capacity 
#
# Properties under /engines/engine[n]:
# + fuel-consumed-lbs - Output from the FDM, zeroed by this script
# + out-of-fuel       - boolean, set by this code.

UPDATE_PERIOD = 0.3;

# ============================== Register timer ===========================================

registerTimer = func {

    settimer(fuelUpdate, UPDATE_PERIOD);
    
}# end func

# ============================= end Register timer =======================================

# =================================== Fuel Update ========================================

fuelUpdate = func {

    var cross_connected =1;
    if(getprop("/sim/freeze/fuel")) { return registerTimer(); }

    if (flag and !done) {print("Camel fuel running"); done = 1};

    AllEngines = props.globals.getNode("engines").getChildren("engine");
		PortEngine = props.globals.getNode("engines").getChild("engine",0);
		StbdEngine = props.globals.getNode("engines").getChild("engine",1);
		port_fuel = PortEngine.getNode("fuel-consumed-lbs",1);
		stbd_fuel = StbdEngine.getNode("fuel-consumed-lbs",1);
		AllEnginescontrols = props.globals.getNode("controls/engines").getChildren("engine");

    # Sum the consumed fuel
    total = 0;
		if (cross_connected){
			foreach(e; AllEngines) {
					fuel = e.getNode("fuel-consumed-lbs", 1);
					consumed = fuel.getValue();
					#print ("consumed ", consumed);
					if(consumed == nil) { consumed = 0; }
					total = total + consumed;
					fuel.setDoubleValue(0);
					}
			} else {
				print ( " port_fuel ",port_fuel.getValue() );
				print ( " stbd_fuel ",stbd_fuel.getValue() );
				port_fuel_consumed = port_fuel.getValue();
				stbd_fuel_consumed = stbd_fuel.getValue();
				if(port_fuel_consumed == nil) {port_fuel_consumed = 0; }
				if(stbd_fuel_consumed == nil) {stbd_fuel_consumed = 0; }
				total = port_fuel_consumed + stbd_fuel_consumed;
				port_fuel.setDoubleValue(0);
				stbd_fuel.setDoubleValue(0);
			}
		
    # Unfortunately, FDM initialization hasn't happened when we start
    # running.  Wait for the FDM to start running before we set any output
    # properties.  This also prevents us from mucking with FDMs that
    # don't support this fuel scheme.
    if(total == 0 and !flag) {  # this relies on 'total'
        return registerTimer(); #  not being quite 0 at startup,
        }else{                  # and therefore keeps the function running,
        flag = 1;               # once it has run once.
    }
        
    if(!initialized) { initialize(); }

    AllTanks = props.globals.getNode("consumables/fuel").getChildren("tank");

    # Build a list of available tanks. An available tank is both selected and has 
    # fuel remaining.  Note the filtering for "zero-capacity" tanks.  The FlightGear
    # code likes to define zombie tanks that have no meaning to the FDM,
    # so we have to take measures to ignore them here. 
    availableTanks = [];
    
    foreach(t; AllTanks) {
        cap = t.getNode("capacity-gal_us", 1).getValue();
        contents = t.getNode("level-gal_us", 1).getValue();
        if(cap != nil and cap > 0.01 ) {
            if(t.getNode("selected", 1).getBoolValue() and contents > 0) {
                append(availableTanks, t);
            }
        }
    }

    # Subtract fuel from tanks, set auxilliary properties.  Set out-of-fuel
    # when all tanks are dry. 
    
		if (cross_connected) {
		
			outOfFuel = 0;
			
			if(size(availableTanks) == 0) {
							outOfFuel = 1;
					} else {
					fuelPerTank = total / size(availableTanks);
					foreach(t; availableTanks) {
							ppg = t.getNode("density-ppg").getValue();
						# lbs = t.getNode("level-gal_us").getValue() * ppg;
					    lbs = t.getNode("level-lbs").getValue();
							lbs = lbs - fuelPerTank;
							if(lbs < 0) {
									lbs = 0; 
									# Kill the engines if we're told to, otherwise simply
									# deselect the tank.
									if(t.getNode("kill-when-empty", 1).getBoolValue()) { outOfFuel = 1; }
									else { t.getNode("selected", 1).setBoolValue(0); }
							 }
							 gals = lbs / ppg;
							 t.getNode("level-gal_us").setDoubleValue(gals);
							 t.getNode("level-lbs").setDoubleValue(lbs);
					}
			}
		
		# set all tanks 
		foreach(t; AllTanks) {
				ppg = t.getNode("density-ppg").getValue();
					t.getNode("level-gal_us").setValue(t.getNode("level-lbs").getValue() / ppg);
			}
		
			
	  #set all engines		
		foreach(e; AllEngines) {
				e.getNode("out-of-fuel").setBoolValue(outOfFuel);
			}
			
			
	
	} else { # we are feeding an engine from each side
		#port side tank and engine
		
		PortTank = props.globals.getNode("consumables/fuel").getChild("tank",0);
		
		outOfFuel = 0;
			if( PortTank.getNode("level-gal_us").getValue() == 0 and 
				PortTank.getNode("selected") ) {
				outOfFuel = 1;
			} else {
				ppg = PortTank.getNode("density-ppg").getValue();
			# lbs = PortTank.getNode("level-gal_us").getValue() * ppg;
				lbs = PortTank.getNode("level-lbs").getValue();
				lbs = lbs - port_fuel_consumed;
				print ( "port fuel ", lbs , " " , port_fuel_consumed);
				if(lbs < 0) {
					lbs = 0; 
					# Kill the engines if we're told to, otherwise simply
					# deselect the tank.
					if(PortTank.getNode("kill-when-empty", 1).getBoolValue()) { outOfFuel = 1; }
					else { PortTank.getNode("selected", 1).setBoolValue(0); }
				 }
				 gals = lbs / ppg;
				 PortTank.getNode("level-gal_us").setDoubleValue(gals);
				 PortTank.getNode("level-lbs").setDoubleValue(lbs);
			} #endif
			
			#set engine
			PortEngine.getNode("out-of-fuel").setBoolValue(outOfFuel);
				 
	#stbd side tank and engine
		
		StbdTank = props.globals.getNode("consumables/fuel").getChild("tank",1);
		
		outOfFuel = 0;
				if( StbdTank.getNode("level-gal_us").getValue() == 0 and 
					StbdTank.getNode("selected") ) {
					outOfFuel = 1;
				} else {
					ppg = StbdTank.getNode("density-ppg").getValue();
				# lbs = StbdTank.getNode("level-gal_us").getValue() * ppg;
					lbs = StbdTank.getNode("level-lbs").getValue();
					lbs = lbs - stbd_fuel_consumed;
					print ( "Stbd fuel ", lbs , " " , stbd_fuel_consumed);
					if(lbs < 0) {
							lbs = 0; 
							# Kill the engines if we're told to, otherwise simply
							# deselect the tank.
							if(StbdTank.getNode("kill-when-empty", 1).getBoolValue()) { outOfFuel = 1; }
							else { StbdTank.getNode("selected", 1).setBoolValue(0); }
					 }
					 gals = lbs / ppg;
					 StbdTank.getNode("level-gal_us").setDoubleValue(gals);
					 StbdTank.getNode("level-lbs").setDoubleValue(lbs);
				} #endif
				
				#set engine
				StbdEngine.getNode("out-of-fuel").setBoolValue(outOfFuel);
		
		
	}	#endif
	
	# Total fuel properties
	total_gals = total_lbs = total_cap = 0;
	ppg = lbs = 0;
	
	foreach(t; AllTanks) {
			ppg = t.getNode("density-ppg").getValue();
			lbs = t.getNode("level-gal_us").getValue() * ppg;
			t.getNode("level-lbs").setDoubleValue(lbs);
			total_cap = cap + t.getNode("capacity-gal_us").getValue();
			total_gals = gals + t.getNode("level-gal_us").getValue();
			total_lbs = lbs + t.getNode("level-lbs").getValue();
			
			
	}
	
	setprop("/consumables/fuel/total-fuel-gals", total_gals);
	setprop("/consumables/fuel/total-fuel-lbs", total_lbs);
	setprop("/consumables/fuel/total-fuel-norm", total_gals/total_cap);
			
  registerTimer(); 
	 
}# end func

# ================================ end Fuel Update ================================

# ================================ Initalize ====================================== 
# Make sure all needed properties are present and accounted
# for, and that they have sane default values.
flag = 0;
done = 0;
initialized = 0;



initialize = func {

    AllEngines = props.globals.getNode("engines").getChildren("engine");
    AllTanks = props.globals.getNode("consumables/fuel").getChildren("tank");
    AllEnginescontrols = props.globals.getNode("controls/engines").getChildren("engine");

    foreach(e; AllEngines) {
        e.getNode("fuel-consumed-lbs", 1).setDoubleValue(0);
        e.getNode("out-of-fuel", 1).setBoolValue(0);
    }

    foreach(t; AllTanks) {
        initDoubleProp(t, "level-gal_us", 0);
        initDoubleProp(t, "level-lbs", 0);
        initDoubleProp(t, "capacity-gal_us", 0.01); # Not zero (div/zero issue)
        initDoubleProp(t, "density-ppg", 6.0); # gasoline

        if(t.getNode("selected") == nil) {
            t.getNode("selected", 1).setBoolValue(1);
        }
    }
    
    foreach(e; AllEnginescontrols) {
        if(e.getNode("mixture-lever") == nil) {
            e.getNode("mixture-lever", 1).setDoubleValue(0);
        }
    }
    
    
    initialized = 1;
    
}# end func

# ================================ end Initalize ================================== 

# =============================== Utility Function ================================

initDoubleProp = func {

    node = arg[0]; prop = arg[1]; val = arg[2];
    if(node.getNode(prop) != nil) {
        val = num(node.getNode(prop).getValue());
    }
    node.getNode(prop, 1).setDoubleValue(val);

}# end func

# =========================== end Utility Function ================================

# Fire it up

registerTimer();
