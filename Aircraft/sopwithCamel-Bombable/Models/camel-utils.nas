#####################################################################################
#                                                                                   #
#  this script contains a number of utilities for use with the Camel (YASim fdm)    #
#                                                                                   #
#####################################################################################

# ================================ Initialize ======================================
# Make sure all needed properties are present and accounted
# for, and that they have sane default values.

aircraft.livery.init("Aircraft/sopwithCamel-Bombable/Models/Liveries",
                     "sim/model/livery/name",
                     "sim/model/livery/index"
                     );

view_number_Node = props.globals.getNode("/sim/current-view/view-number",1);
view_number_Node.setDoubleValue( 0 );

enabledNode = props.globals.getNode("/sim/headshake/enabled", 1);
enabledNode.setBoolValue(1);

instrumentation_yawstring_Node = props.globals.getNode("instrumentation/yawstring[0]", 1);
instrumentation_yawstring_Node.setValue(0);

instrumentation_airstring_Node = props.globals.getNode("instrumentation/airstring[0]", 1);
instrumentation_airstring_Node.setValue(0);

instrumentation_yawstring_flutter_Node = props.globals.getNode("instrumentation/yawstring-flutter[0]", 1);
instrumentation_yawstring_flutter_Node.setValue(0);

generic_float0_Node = props.globals.getNode("sim/multiplay/generic/float[0]", 1);
generic_float0_Node.setValue(0);

generic_float1_Node = props.globals.getNode("sim/multiplay/generic/float[1]", 1);
generic_float1_Node.setValue(0);

generic_float2_Node = props.globals.getNode("sim/multiplay/generic/float[2]", 1);
generic_float2_Node.setValue(0);

sim_model_camel_show_pilot_Node = props.globals.getNode("sim/model/camel/show-pilot[0]", 1);
sim_model_camel_show_pilot_Node.setBoolValue(1);

sim_model_camel_show_face_mask_Node = props.globals.getNode("sim/model/camel/show-face-mask[0]", 1);
sim_model_camel_show_face_mask_Node.setBoolValue(0);

generic_bool0_Node = props.globals.getNode("sim/multiplay/generic/int[0]", 1);
generic_bool0_Node.setBoolValue(0);

controls_gear_brake_parking_Node = props.globals.getNode("controls/gear/brake-parking[0]", 1);
sim_model_camel_show_pilot_Node.setBoolValue(0);

generic_bool1_Node = props.globals.getNode("sim/multiplay/generic/int[1]", 1);
generic_bool1_Node.setBoolValue(0);


controls.fullBrakeTime = 0;

pilot_g = nil;
headshake = nil;
magneto = nil;
smoke = nil;


var time = 0;
var dt = 0;
var last_time = 0.0;

var xDivergence_damp = 0;
var yDivergence_damp = 0;
var zDivergence_damp = 0;

var last_xDivergence = 0;
var last_yDivergence = 0;
var last_zDivergence = 0;

initialize = func {

    print( "Initializing Camel utilities ..." );

# initialize objects
    pilot_g = PilotG.new();
    headshake = HeadShake.new();
    magneto = Magneto.new();
    smoke = Smoke.new();

#set listeners
    setlistener( "controls/gear/brake-left", func { magneto.blipMagswitch();
    } );
    setlistener( "controls/gear/brake-right", func { magneto.blipMagswitch();
    } );

    setlistener( "engines/engine/cranking", func { smoke.updateSmoking();
    } );
    setlistener( "engines/engine/running", func { smoke.updateSmoking();
    } );

    setlistener( "sim/model/camel/show-face-mask[0]", func {
                generic_bool0_Node.setValue(sim_model_camel_show_face_mask_Node.getValue());
            } );

    setlistener( "controls/gear/brake-parking", func {
                if(getprop("gear/gear[0]/wow") and getprop("gear/gear[1]/wow")){
                    generic_bool1_Node.setValue(controls_gear_brake_parking_Node.getValue());
                }
            } );

    setlistener( "fdm/jsbsim/fcs/automixture-enable", func { displaymixturetoggle();
    } );
    



# set it running on the next update cycle
    settimer( update, 0 );

    print( "... running Camel utilities" );

} # end func

###
# ====================== end Initialization ========================================
###

###
# ==== this is the Main Loop which keeps everything updated ========================
##
update = func {

    generic_float0_Node.setValue(instrumentation_yawstring_Node.getValue());
    generic_float1_Node.setValue(instrumentation_airstring_Node.getValue());
    generic_float2_Node.setValue(instrumentation_yawstring_flutter_Node.getValue());

    pilot_g.update();
    pilot_g.gmeter_update();

    if ( enabledNode.getValue() and view_number_Node.getValue() == 0 ) {
        headshake.update();
    }

    settimer( update, 0 );

}# end main loop func

# ============================== end Main Loop ===============================

# ============================== specify classes ===========================



# =================================== fuel tank stuff ===================================
# Class that specifies fuel cock functions
#
FuelCock = {
    new : func ( name,
    control,
    initial_pos
    ){
        var obj = { parents : [FuelCock] };
        obj.name = name;
        obj.control = props.globals.getNode( control, 1 );
        obj.control.setIntValue( initial_pos );

        print ( obj.name );
        return obj;
    },

set: func ( pos ) {# operate fuel cock
     me.control.setValue( pos );
    },
}; #



# ========================== end fuel tank stuff ======================================


# =========================== magneto stuff ====================================
# Class that specifies magneto functions
#
Magneto = {
    new : func ( name = "magneto",
    right = "controls/engines/engine/mag-switch-right",
    left = "controls/engines/engine/mag-switch-left",
    magnetos = "controls/engines/engine/magnetos",
    left_brake = "controls/gear/brake-left",
    right_brake = "controls/gear/brake-right"
    ){
        var obj = { parents : [Magneto] };
        obj.name = name;
        obj.right = props.globals.getNode( right, 1 );
        obj.left = props.globals.getNode( left, 1 );
        obj.magnetos = props.globals.getNode( magnetos, 1 );
        obj.left_brake = props.globals.getNode( left_brake, 1 );
        obj.right_brake = props.globals.getNode( right_brake, 1 );
        obj.left.setBoolValue( 0 );
        obj.right.setBoolValue( 0 );
        print ( obj.name );
        return obj;
    },

updateMagnetos: func{     # set the magneto value according to the switch positions
# print("updating Magnetos");
                if (me.left.getValue() and me.right.getValue()){                  # both
                    me.magnetos.setValue( 3 );
                }
                elsif (me.left.getValue() and !me.right.getValue()) {             # left
                    me.magnetos.setValue( 1 );
                }
                elsif (!me.left.getValue() and me.right.getValue()) {             # right
                    me.magnetos.setValue( 2 );
                }
                else{
                    me.magnetos.setValue( 0 );            # none
                }

    }, # end function

setleftMagswitch:   func ( left ) {

    me.left.setValue( left );
    me.updateMagnetos();

    }, # end function

setrightMagswitch:  func ( right) {

    me.right.setValue( right );
    me.updateMagnetos();

    }, # end function

toggleleftMagswitch:    func{
# print ("left in ", me.left.getValue());
    var left = me.left.getValue();
    left = !left;
    me.left.setBoolValue( left );
    me.updateMagnetos();

    }, # end function

togglerightMagswitch:   func{
# print ("right in ", me.right.getValue());
    var right = me.right.getValue();
    right = !right;
    me.right.setBoolValue( right );
    me.updateMagnetos();

    }, # end function

blipMagswitch:   func{
# print ("blip in right ", me.right.getValue()," left ", me.left.getValue());
# print ("blip in right ", me.right_brake.getValue()," left ", me.left_brake.getValue());
    # was value !=0 for brakes, but with rudder/pedals the brake values
    # are often not that precise
    # If the brake value rides at 0.0002 then the engine keeps cutting out
    # Setting the threshold higher solves the problem
    # camel.inverted_out_of_fuel - see jsbsim.nas - this disables the blip
    # switch when the camel is out of fuel because it is inverted
    print ("oof ", camel.inverted_out_of_fuel);                       
    if ( camel.inverted_out_of_fuel ) return;
    if ( me.right_brake.getValue() > 0.25 or me.left_brake.getValue() > 0.25 
            ) {;
        me.magnetos.setValue( 0 );
        setprop("sim/model/camel/blip_switch",1);
    } else {
        me.updateMagnetos();
        setprop("sim/model/camel/blip_switch",0);
    }

# print ("blip out right ", me.right.getValue()," left ", me.left.getValue());
    }, # end function
    }; #


# =============================== end magneto stuff =========================================

# =============================== Pilot G stuff ================================
# Class that specifies pilot g functions
#
    PilotG = {
        new : func ( name = "pilot-g",
        acceleration = "accelerations",
        pilot_g = "pilot-g",
        g_timeratio = "timeratio",
        pilot_g_damped = "pilot-gdamped",
        g_min = "pilot-gmin",
        g_max = "pilot-gmax"
        ){
            var obj = { parents : [PilotG] };
            obj.name = name;
            obj.accelerations = props.globals.getNode("accelerations", 1);
            obj.pilot_g = obj.accelerations.getChild( pilot_g, 0, 1 );
            obj.pilot_g_damped = obj.accelerations.getChild( pilot_g_damped, 0, 1 );
            obj.g_timeratio = obj.accelerations.getChild( g_timeratio, 0, 1 );
            obj.g_min = obj.accelerations.getChild( g_min, 0, 1 );
            obj.g_max = obj.accelerations.getChild( g_max, 0, 1 );
            obj.pilot_g.setDoubleValue(0);
            obj.pilot_g_damped.setDoubleValue(0);
            obj.g_timeratio.setDoubleValue(0.0075);
            obj.g_min.setDoubleValue(0);
            obj.g_max.setDoubleValue(0);

            print ( obj.name );
            return obj;
        },
update : func () {
        var n = me.g_timeratio.getValue();
        var g = me.pilot_g.getValue();
        var g_damp = me.pilot_g_damped.getValue();

        g_damp = ( g * n) + (g_damp * (1 - n));

        me.pilot_g_damped.setDoubleValue(g_damp);

# print(sprintf("pilot_g_damped in=%0.5f, out=%0.5f", g, g_damp));
        },
gmeter_update : func () {
        if( me.pilot_g_damped.getValue() < me.g_min.getValue() ){
            me.g_min.setDoubleValue( me.pilot_g_damped.getValue() );
        } elsif( me.pilot_g_damped.getValue() > me.g_max.getValue() ){
            me.g_max.setDoubleValue( me.pilot_g_damped.getValue() );
        }
        },
get_g_timeratio : func () {
        return me.g_timeratio.getValue();
        },
    };	



# Class that specifies head movement functions under the force of gravity
# 
#  - this is a modification of the original work by Josh Babcock

    HeadShake = {
        new : func ( name = "headshake",
        x_accel_fps_sec = "x-accel-fps_sec",
        y_accel_fps_sec = "y-accel-fps_sec",
        z_accel_fps_sec = "z-accel-fps_sec",
        x_max_m = "x-max-m",
        x_min_m = "x-min-m",
        y_max_m = "y-max-m",
        y_min_m = "y-min-m",
        z_max_m = "z-max-m",
        z_min_m = "z-min-m",
        x_threshold_g = "x-threshold-g",
        y_threshold_g = "y-threshold-g",
        z_threshold_g = "z-threshold-g",
        x_config = "z-offset-m", 
        y_config = "x-offset-m",
        z_config = "y-offset-m",
        time_ratio = "time-ratio",
        ){
            var obj = { parents : [HeadShake] };
            obj.name = name;
            obj.accelerations = props.globals.getNode( "accelerations/pilot", 1 );
            obj.xAccelNode = obj.accelerations.getChild(  x_accel_fps_sec, 0, 1 );
            obj.yAccelNode = obj.accelerations.getChild(  y_accel_fps_sec, 0, 1 );
            obj.zAccelNode = obj.accelerations.getChild(  z_accel_fps_sec, 0, 1 );
            obj.sim = props.globals.getNode( "sim/headshake", 1 );
            obj.xMaxNode = obj.sim.getChild( x_max_m, 0, 1 );
            obj.xMaxNode.setDoubleValue( 0.025 );
            obj.xMinNode = obj.sim.getChild( x_min_m, 0, 1 );
            obj.xMinNode.setDoubleValue( -0.01 );
            obj.yMaxNode = obj.sim.getChild( y_max_m, 0, 1 );
            obj.yMaxNode.setDoubleValue( 0.01 );
            obj.yMinNode = obj.sim.getChild( y_min_m, 0, 1 );
            obj.yMinNode.setDoubleValue( -0.01 );
            obj.zMaxNode = obj.sim.getChild( z_max_m, 0, 1 );
            obj.zMaxNode.setDoubleValue( 0.01 );
            obj.zMinNode = obj.sim.getChild( z_min_m, 0, 1 );
            obj.zMinNode.setDoubleValue( -0.03 );
            obj.xThresholdNode = obj.sim.getChild(x_threshold_g, 0, 1 );
            obj.xThresholdNode.setDoubleValue( 0.5 );
            obj.yThresholdNode = obj.sim.getChild(y_threshold_g, 0, 1 );
            obj.yThresholdNode.setDoubleValue( 0.5 );
            obj.zThresholdNode = obj.sim.getChild(z_threshold_g, 0, 1 );
            obj.zThresholdNode.setDoubleValue( 0.5 );
            obj.time_ratio_Node = obj.sim.getChild( time_ratio , 0, 1 );
            obj.time_ratio_Node.setDoubleValue( 0.5 );
            obj.config = props.globals.getNode("/sim/view/config", 1);
            obj.xConfigNode = obj.config.getChild( x_config , 0, 1 );
            obj.yConfigNode = obj.config.getChild( y_config , 0, 1 );
            obj.zConfigNode = obj.config.getChild( z_config , 0, 1 );

            obj.seat_vertical_adjust_Node = props.globals.getNode( "/controls/seat/vertical-adjust", 1 );
            obj.seat_vertical_adjust_Node.setDoubleValue( 0 );

            print ( obj.name );
            return obj;
        },
update : func () {

# There are two coordinate systems here, one used for accelerations, 
# and one used for the viewpoint.
# We will be using the one for accelerations.

        var n = pilot_g.get_g_timeratio(); 
        var seat_vertical_adjust = me.seat_vertical_adjust_Node.getValue();

        var xMax = me.xMaxNode.getValue();
        var xMin = me.xMinNode.getValue();
        var yMax = me.yMaxNode.getValue();
        var yMin = me.yMinNode.getValue();
        var zMax = me.zMaxNode.getValue();
        var zMin = me.zMinNode.getValue();

#work in G, not fps/s
        var xAccel = me.xAccelNode.getValue()/32;
        var yAccel = me.yAccelNode.getValue()/32;
        var zAccel = (me.zAccelNode.getValue() + 32)/32; # We aren't counting gravity

            var xThreshold =  me.xThresholdNode.getValue();
        var yThreshold =  me.yThresholdNode.getValue();
        var zThreshold =  me.zThresholdNode.getValue();

        var xConfig = me.xConfigNode.getValue();
        var yConfig = me.yConfigNode.getValue();
        var zConfig = me.zConfigNode.getValue();

# Set viewpoint divergence and clamp
# Note that each dimension has its own special ratio and +X is clamped at 1cm
# to simulate a headrest.

        if (xAccel < -1) {
            xDivergence = ((( -0.0506 * xAccel ) - ( 0.538 )) * xAccel - ( 0.9915 ))
                * xAccel - 0.52;
        } elsif (xAccel > 1) {
            xDivergence = ((( -0.0387 * xAccel ) + ( 0.4157 )) * xAccel - ( 0.8448 )) 
                * xAccel + 0.475;
        } else {
            xDivergence = 0;
        }

        if (yAccel < -0.5) {
            yDivergence = ((( -0.013 * yAccel ) - ( 0.125 )) * yAccel - (  0.1202 )) * yAccel - 0.0272;
        } elsif (yAccel > 0.5) {
            yDivergence = ((( -0.013 * yAccel ) + ( 0.125 )) * yAccel - (  0.1202 )) * yAccel + 0.0272;
        } else {
            yDivergence = 0;
        }

        if (zAccel < -1) {
            zDivergence = ((( -0.0506 * zAccel ) - ( 0.538 )) 
                * zAccel - ( 0.9915 )) * zAccel - 0.52;
        } elsif (zAccel > 1) {
            zDivergence = ((( -0.0387 * zAccel ) + ( 0.4157 )) 
                * zAccel - ( 0.8448 )) * zAccel + 0.475;
        } else {
            zDivergence = 0;
        }

        xDivergence_total = ( xDivergence * 0.25 ) + ( zDivergence * 0.25 );

        if (xDivergence_total > xMax){ xDivergence_total = xMax; }
        if (xDivergence_total < xMin){ xDivergence_total = xMin; }
        if (abs(last_xDivergence - xDivergence_total) <= xThreshold){
            xDivergence_damp = ( xDivergence_total * n) + ( xDivergence_damp * (1 - n));
#	print ("x low pass");
        } else {
            xDivergence_damp = xDivergence_total;
#	print ("x high pass");
        }

        last_xDivergence = xDivergence_damp;

#print (sprintf("x total=%0.5f, x min=%0.5f, x div damped=%0.5f", xDivergence_total,
# xMin , xDivergence_damp));	

        yDivergence_total = yDivergence;
        if ( yDivergence_total >= yMax ){ yDivergence_total = yMax; }
        if ( yDivergence_total <= yMin ){ yDivergence_total = yMin; }

        if (abs(last_yDivergence - yDivergence_total) <= yThreshold){
            yDivergence_damp = ( yDivergence_total * n) + ( yDivergence_damp * (1 - n));
#	 	print ("y low pass");
        } else {
            yDivergence_damp = yDivergence_total;
#		print ("y high pass");
        }

        last_yDivergence = yDivergence_damp;

#	print (sprintf("y=%0.5f, y total=%0.5f, y min=%0.5f, y div damped=%0.5f",
#						yDivergence, yDivergence_total, yMin , yDivergence_damp));

        zDivergence_total =  xDivergence + zDivergence;
        if ( zDivergence_total >= zMax ){ zDivergence_total = zMax; }
        if ( zDivergence_total <= zMin ){zDivergence_total = zMin; }

        if (abs(last_zDivergence - zDivergence_total) <= zThreshold){ 
            zDivergence_damp = ( zDivergence_total * n) + ( zDivergence_damp * (1 - n));
#	print ("z low pass");
        } else {
            zDivergence_damp = zDivergence_total;
#	print ("z high pass");
        }

        last_zDivergence = zDivergence_damp;

#	print (sprintf("z total=%0.5f, z min=%0.5f, z div damped=%0.5f", 
#										zDivergence_total, zMin , zDivergence_damp));

        setprop( "/sim/current-view/z-offset-m", xConfig + xDivergence_damp );
        setprop( "/sim/current-view/x-offset-m", yConfig + yDivergence_damp );
        setprop( "/sim/current-view/y-offset-m", zConfig + zDivergence_damp 
            + seat_vertical_adjust );

        },
    };


# ============================ end Pilot G stuff ============================

# =========================== smoke stuff ====================================
# Class that specifies smoke functions 
#
    Smoke = {
        new : func ( name = "smoke",
        cranking = "engines/engine/cranking",
        running = "engines/engine/running",
        smoking = "sim/ai/engines/engine/smoking"
        ){
            var obj = { parents : [Smoke] };
            obj.name = name;
            obj.cranking = props.globals.getNode( cranking, 1 );
            obj.running = props.globals.getNode( running, 1 );
            obj.smoking = props.globals.getNode( smoking, 1 );
            obj.smoking.setBoolValue( 0 );
            print ( obj.name );
            return obj;
        },

updateSmoking: func{     # set the smoke value according to the engine conditions
#		print("updating Smoke");
               if (me.cranking.getValue() and !me.running.getValue()){  
                   me.smoking.setValue( 1 );
               } else{
                   me.smoking.setValue( 0 );            # none
               }

        }, # end function

    }; #


# =============================== end smoke stuff ==============================



#displays message showing whether auto mixture is enabled/disabled.
var displaymixturetoggle = func {
    if ( getprop("fdm/jsbsim/fcs/automixture-enable") ){
      msg="Automixture enabled - attempts to maintain 1250 RPM";
    } else {
      msg="Manual mixture enabled (realistic) - use 'm' and 'M' keys to set mixture";
      
      settimer( displaymixture, 5 );
      
    }
    camelStatusPopupTip (msg, 5);
    
}

var displaymixture = func {
    if ( ! getprop("fdm/jsbsim/fcs/automixture-enable") ){
      var mix = getprop ("controls/engines/engine/mixture");
      var rpm = getprop ("engines/engine/rpm"); 
      msg = sprintf( "Mixture: %1.0f%%  RPM: %1.0f", mix*100, rpm);
      camelStatusPopupTip (msg, .6);  #.6 to avoid little display glitches.
      settimer( displaymixture, .5 );
    }
    
    
}

# ========== popup dialog message===============================================

tipArgCamel = props.Node.new({ "dialog-name" : "PopTipCamel" });
currTimerCamel=0;
  
var camelStatusPopupTip = func (label, delay = 10, override = nil) {	
    #return; #gui prob
    var tmpl = props.Node.new({
            name : "PopTipCamel", modal : 0, layout : "hbox",
            y: 210,
            text : { label : label, padding : 6 }
    });
    if (override != nil) tmpl.setValues(override);
   
    popdown(tipArgCamel);
    fgcommand("dialog-new", tmpl);
    fgcommand("dialog-show", tipArgCamel);

    currTimerCamel += 1;
    var thisTimerCamel = currTimerCamel;

    # Final argument is a flag to use "real" time, not simulated time
    settimer(func { if(currTimerCamel == thisTimerCamel) { popdown(tipArgCamel) } }, delay, 1);
}

var popdown = func ( tipArg ) { 
  #return; #gui prob
  fgcommand("dialog-close", tipArg); 
}


# =========================main initializer=====================================

# Fire it up

    settimer(initialize,0);

# end 
