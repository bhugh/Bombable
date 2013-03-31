##########################################################
# General initializers
#  
#todo: These ammo weights are not correct for the A6M2
var ammo_weight=1.4/20; # 20 rounds of .303 180gr ammo weighs 1.4 pounds 
                    # per http://www.ammo-sale.com/proddetail.asp?prod=1699# 


var r_cannon_ammo_count="ai/submodels/submodel[0]/count";  
var l_cannon_ammo_count="ai/submodels/submodel[3]/count";
var r_cannon_tracer_count="ai/submodels/submodel[1]/count"; 
var l_cannon_tracer_count="ai/submodels/submodel[4]/count";
var r_cannon_smoke_count="ai/submodels/submodel[2]/count";
var l_cannon_smoke_count="ai/submodels/submodel[5]/count";

var r_gun_ammo_count="ai/submodels/submodel[6]/count";  
var l_gun_ammo_count="ai/submodels/submodel[9]/count";
var r_gun_tracer_count="ai/submodels/submodel[7]/count"; 
var l_gun_tracer_count="ai/submodels/submodel[10]/count";
var r_gun_smoke_count="ai/submodels/submodel[8]/count";
var l_gun_smoke_count="ai/submodels/submodel[11]/count";


var r_ammo_weight="yasim/weights/ammo-r-lb";
var l_ammo_weight="yasim/weights/ammo-l-lb";


    


##############################################################
#reload guns
#
# Guns generally cannot be reloaded in flight--so if you are out
# of ammo, land and re-load.
#

reload_guns  = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  #only allow it if on ground, stopped OR if it's already set to unlimited mode
  if ( ( groundspeed < 5 and engine_rpm < 5 )  
         or getprop ( r_gun_ammo_count)== -1 ) {
    
    setprop ( r_gun_ammo_count, 500); #ammo r
    setprop ( l_gun_ammo_count, 500); #ammo l
    setprop ( r_gun_tracer_count, 167); #tracer r
    setprop ( l_gun_tracer_count, 167); #tracer l
    setprop ( r_gun_smoke_count, 125); #smoke r
    setprop ( l_gun_smoke_count, 125); #smoke l

    setprop ( r_cannon_ammo_count, 60); #ammo r
    setprop ( l_cannon_ammo_count, 60); #ammo l
    setprop ( r_cannon_tracer_count, 20); #tracer r
    setprop ( l_cannon_tracer_count, 20); #tracer l
    setprop ( r_cannon_smoke_count, 15); #smoke r
    setprop ( l_cannon_smoke_count, 15); #smoke l
    
    gui.popupTip ("Guns reloaded--500 rounds in each gun, 60 in each cannon.", 5)
    
  } else {
   
    gui.popupTip ("You must be on the ground and engines dead stopped to re-load guns.",5)
  
  }

}  

##############################################################
#unlimited ammo
#
#For testing only, of course!
# 

unlimited_guns = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  

    
    setprop ( r_gun_ammo_count, -1); #ammo r
    setprop ( l_gun_ammo_count, -1); #ammo l
    setprop ( r_gun_tracer_count, -1); #tracer r
    setprop ( l_gun_tracer_count, -1); #tracer l
    setprop ( r_gun_smoke_count, -1); #smoke r
    setprop ( l_gun_smoke_count, -1); #smoke l

    setprop ( r_cannon_ammo_count, -1); #ammo r
    setprop ( l_cannon_ammo_count, -1); #ammo l
    setprop ( r_cannon_tracer_count, -1); #tracer r
    setprop ( l_cannon_tracer_count, -1); #tracer l
    setprop ( r_cannon_smoke_count, -1); #smoke r
    setprop ( l_cannon_smoke_count, -1); #smoke l
   
    gui.popupTip ("Guns set to unlimited mode--definitely not realistic and only for testing!  Select 'Reload Guns' to revert to limited ammo.",7)
  
}
