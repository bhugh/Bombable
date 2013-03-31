##########################################################
# General initiatizers
#  
var ammo_weight=1.4/20; # 20 rounds of .303 180gr ammo weighs 1.4 pounds 
                    # per http://www.ammo-sale.com/proddetail.asp?prod=1699# 

var r_gun_ammo_count="ai/submodels/submodel[0]/count";  
var l_gun_ammo_count="ai/submodels/submodel[3]/count";
var r_gun_tracer_count="ai/submodels/submodel[1]/count"; 
var l_gun_tracer_count="ai/submodels/submodel[4]/count";
var r_gun_smoke_count="ai/submodels/submodel[2]/count";
var l_gun_smoke_count="ai/submodels/submodel[5]/count";

var r_ammo_weight="yasim/weights/ammo-r-lb";
var l_ammo_weight="yasim/weights/ammo-l-lb";





##############################################################
#update ammo weight update every 5 seconds
#
# todo: make this work for other FDM other than YASIM
# 
var update_ammo_weight = func {

                         
    setprop (r_ammo_weight, ammo_weight * getprop(r_gun_ammo_count));
    setprop (l_ammo_weight, ammo_weight * getprop(l_gun_ammo_count));

    #updating once every 5 seconds should be sufficient--
    #this is fairly lightweight ammo 
    #and you can only shoot about 4 pounds from each gun in 5 seconds.           
    settimer (update_ammo_weight, 5.12378);
}


##############################################################
#init update ammo weight
#
# todo: make this work for other FDM other than YASIM


#start the timer to update the ammo weights
settimer (update_ammo_weight, 5);
    


##############################################################
#reload guns
#
# According to this source the Vickers couldn't be releoaded 
# in flight--it took a man on the ground and one in the 
# cockpit:
# 
# http://www.theaerodrome.com/forum/aircraft/40149-reloading-guns.html
# 
# This we require landed and engines off before reloading.
# 
# Per this source, British Camels with Vickers guns typically
# loaded 400 rounds:
# 
# http://www.theaerodrome.com/forum/aircraft/29896-bullets-guns.html
# 
# Note that tracers are modeled as bullets that include a visual model but
# no impact.  They fire along with 1 of every four bullets to simulate
# a tracer round every 4 rounds.

reload_guns  = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  #only allow it if on ground, stopped OR if it's already set to unlimited mode
  if ( ( groundspeed < 5 and engine_rpm < 5 )  
         or getprop ( r_gun_ammo_count)== -1 ) {
    
    setprop ( r_gun_ammo_count, 400); #ammo r
    setprop ( l_gun_ammo_count, 400); #ammo l
    setprop ( r_gun_tracer_count, 100); #tracer r
    setprop ( l_gun_tracer_count, 100); #tracer l
    setprop ( r_gun_smoke_count, 400); #smoke r
    setprop ( l_gun_smoke_count, 400); #smoke l
    
    gui.popupTip ("Guns reloaded--an ammunition belt with 400 rounds in each gun.", 5)
    
  } else {
   
    gui.popupTip ("You must be on the ground and engines dead stopped to re-load guns--this is a two-person job with one on the ground and one in the cockpit.",5)
  
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

   
    gui.popupTip ("Guns set to unlimited mode--definitely not realistic and only for testing!  Select 'Reload Guns' to revert to limited ammo.",7)
  
}

 


#print ("gun vibrations init #1");

