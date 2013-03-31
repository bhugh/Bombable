#adjust friction etc per terrain
var terrain_survol = func (id) {

  var loopid=getprop("/environment/terrain-info/terrain_servol_loopid");
  if (loopid==nil) terrain_survol_loopid=0;
  id==loopid or return;
  settimer (func {terrain_survol(id)}, 0.12734);  
  
  var lat = getprop("/position/latitude-deg");
  var lon = getprop("/position/longitude-deg");
  var info = geodinfo(lat, lon);
      if ( (info != nil) and (info[1] != nil)) { 
          if (info[1].solid ==nil) info[1].solid = 1;
          setprop("/environment/terrain-info/terrain",info[1].solid);   # 1 if solid land, 0 if water
          #the crash-detect subroutine can only read within the /fdim/jsbsim hierarchy so we must put this there as well
          setprop("/fdm/jsbsim/terrain-info/terrain",info[1].solid);   # 1 if solid land, 0 if water
          
           
          if (info[1].load_resistance ==nil) info[1].load_resistance = 1e+30;
          setprop("/environment/terrain-info/terrain-load-resistance",info[1].load_resistance);
          
          if (info[1].friction_factor ==nil) info[1].friction_factor = 1.05; 
          setprop("/environment/terrain-info/terrain-friction-factor",info[1].friction_factor);
          
          if (info[1].bumpiness ==nil) info[1].bumpiness = 0;
          
          setprop("/environment/terrain-info/terrain-bumpiness",info[1].bumpiness);
          
          if (info[1].rolling_friction ==nil) info[1].rolling_friction = 0.02;
          
          setprop("/environment/terrain-info/terrain-rolling-friction",info[1].rolling_friction);
          
          if (info[1].names ==nil) info[1].names="";
          setprop("/environment/terrain-info/names",info[1].names[0]); 
                   
      } else {
        setprop("/environment/terrain-info/terrain",1);  # 1 if solid land, 0 if water
        #the crash-detect subroutine can only read within the /fdim/jsbsim hierarchy so we must put this there as well
        setprop("/fdm/jsbsim/terrain-info/terrain",1);   # 1 if solid land, 0 if water

        setprop("/environment/terrain-info/terrain-load-resistance",1e+30);
        setprop("/environment/terrain-info/terrain-friction-factor",1.05);
        setprop("/environment/terrain-info/terrain-bumpiness",0);
        setprop("/environment/terrain-info/terrain-rolling-friction",0.02);
      }
      
  friction_loop();    
  
}




var friction_init =func {
  for (var n=0;n<getprop("/fdm/jsbsim/gear/num-units"); n+=1) {
    
    var x = getprop("/fdm/jsbsim/gear/unit["~n~"]/side_friction_coeff");
    if (x==nil) x=0;
    setprop ("/environment/terrain-info/gear/unit["~n~"]/side_friction_coeff_aircraft",x );
    
    var x = getprop("/fdm/jsbsim/gear/unit["~n~"]/static_friction_coeff");
    if (x==nil) x=0; 
    setprop ("/environment/terrain-info/gear/unit["~n~"]/static_friction_coeff_aircraft", x );

    var x = getprop("/fdm/jsbsim/gear/unit["~n~"]/dynamic_friction_coeff");
    if (x==nil) x=0; 
    setprop ("/environment/terrain-info/gear/unit["~n~"]/dynamic_friction_coeff_aircraft", x );
    
    var x = getprop("/fdm/jsbsim/gear/unit["~n~"]/rolling_friction_coeff");
    if (x==nil) x=0; 
    setprop ("/environment/terrain-info/gear/unit["~n~"]/rolling_friction_coeff_aircraft", x );
    
    print ("Camel/JSBSim: Aircraft friction parameters initialized");
  } 
}  
    
var friction_loop = func {

  for (var n=0;n<getprop("/fdm/jsbsim/gear/num-units"); n+=1) {
    var tff=getprop("/environment/terrain-info/terrain-friction-factor" );
    if (tff==nil) tff=1;
    
    setprop ("/fdm/jsbsim/gear/unit["~n~"]/side_friction_coeff",
     getprop("/environment/terrain-info/gear/unit["~n~"]/side_friction_coeff_aircraft") *
     tff ) ;
    
    var bff= getprop("/environment/terrain-info/gear/unit["~n~"]/static_friction_coeff_aircraft");
    #print (bff==nil, " ", n);
    setprop ("/fdm/jsbsim/gear/unit["~n~"]/static_friction_coeff",
      bff * tff ) ;
    
    setprop ("/fdm/jsbsim/gear/unit["~n~"]/dynamic_friction_coeff",
     getprop("/environment/terrain-info/gear/unit["~n~"]/dynamic_friction_coeff_aircraft") *
     tff);    
     
    setprop ("/fdm/jsbsim/gear/unit["~n~"]/rolling_friction_coeff",
     getprop("/environment/terrain-info/gear/unit["~n~"]/rolling_friction_coeff_aircraft") +
     getprop("/environment/terrain-info/terrain-rolling-friction" ) ) ;
     
  } 
  
  #print ("Camel/JSBSim: Friction parameters updated");
}  

var setCrash= func {
 var crashed = getprop("/fdm/jsbsim/systems/crash-detect/crashed");
 if (!crashed) return;
 
 #only do this if we've been un-crashed for at least 3 seconds
 var setCrash_thisPause_systime=systime();
 print ("Crash: Time diff:", setCrash_thisPause_systime, " ", setCrash_lastPause_systime);
 var timeSinceLastCrash = setCrash_thisPause_systime - setCrash_lastPause_systime;
 setCrash_lastPause_systime=setCrash_thisPause_systime;
 if ( timeSinceLastCrash < 3 ) return;
 
 var  crashCause = "Airplane crashed, FlightGear paused ";
 var impact = getprop("/fdm/jsbsim/systems/crash-detect/impact");
 var impact_water = getprop("/fdm/jsbsim/systems/crash-detect/impact-water");
 var over_g = getprop("/fdm/jsbsim/systems/crash-detect/over-g");
 var current_g = getprop("/fdm/jsbsim/accelerations/Nz"); 
 
 if (impact) crashCause ~=" - Ground impact ";
 if (impact_water) {
     crashCause ~=" - Water impact ";
     #Ok, this doesnt' work rem-ing it out.
     #sink(10, .1, .5);
 }   
 if (over_g) crashCause ~= sprintf( " - G force %1.1f G exceeded 15G, aircraft destroyed ", current_g);
 
 #freeze/pause/crash
 setprop ("/sim/freeze/clock", 1);
 setprop ("/sim/freeze/master", 1);

 camel.dialog.init(450, 0, crashCause); camel.dialog.create(crashCause);

 #setprop ("/sim/crashed", 1);

}

#sinks the ship, glug . . . glug . . . glug
# OK, it doesn't work bec. JSBSim keeps putting the craft on top of the surface again.
var sink = func (distance_ft, rate_ft_per_cycle, time_sec) {
 setprop ("/position/altitude-ft", getprop ("/position/altitude-ft") - rate_ft_per_cycle);
 distance_ft-=rate_ft_per_cycle;
 if (distance_ft<0) return;
 settimer ( func { sink (distance_ft,rate_ft_per_cycle, time_sec) }, time_sec);

}

friction_init();
var terrain_survol_loopid=getprop("/environment/terrain-info/terrain_servol_loopid");
if (terrain_survol_loopid==nil) terrain_survol_loopid=0;
terrain_survol_loopid+=1;
setprop("/environment/terrain-info/terrain_servol_loopid", terrain_survol_loopid);
terrain_survol(terrain_survol_loopid);  

#removelistener(list1);
var setCrash_lastPause_systime=systime();
var list1 = setlistener ( "/fdm/jsbsim/systems/crash-detect/crashed", func { setCrash() },0,0 );









