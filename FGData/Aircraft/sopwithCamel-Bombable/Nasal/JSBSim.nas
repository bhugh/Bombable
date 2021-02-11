print ("Camel: Starting JSBSim.nas");

###########################################################################
#
#VARIOUS INITIALIZERS for routines below 
#

#start with chocks in by default
setprop("controls/gear/brake-parking",1);

var right_bump_lowpass = aircraft.lowpass.new(0.2);
var left_bump_lowpass = aircraft.lowpass.new(0.2);
var tail_bump_lowpass = aircraft.lowpass.new(0.2);


###END INITIALIZERS ###########################################################

	
###############################################################################
#
#ADJUST FRICTION PARAMETERS PER TERRAIN
#
# 

#loop start or re-start
var terrain_servol_loop_start = func () {
  var terrain_survol_loopid=getprop("/environment/terrain-info/terrain_servol_loopid");
  if (terrain_survol_loopid==nil) terrain_survol_loopid=0;
  terrain_survol_loopid+=1;
  setprop("/environment/terrain-info/terrain_servol_loopid", terrain_survol_loopid);
  terrain_survol(terrain_survol_loopid);
}

var SCJ_readytoquit=0;

#main loop: adjust friction etc per terrain etc
var terrain_survol = func (id) {

  var loopid=getprop("/environment/terrain-info/terrain_servol_loopid");
  if (loopid==nil) terrain_survol_loopid=0;
  id==loopid or return;
  settimer (func {terrain_survol(id)}, 0.04734);  
  #settimer (func {terrain_survol(id)}, 0.016666); #experimentally going 2X as fast
  
  var agl_ft = getprop("/fdm/jsbsim/position/h-agl-ft");
  var agl_ft_alt = getprop("/position/altitude-agl-ft");
  
  #transfer the mag switch settings, which we can then use to control the engine in various ways
  var l_mag = getprop ("/controls/engines/engine/mag-switch-left");
  var r_mag = getprop ("/controls/engines/engine/mag-switch-right");
  if (typeof(l_mag)=="nil") l_mag=0;
  if (typeof(r_mag)=="nil") r_mag=0;
  setprop ("fdm/jsbsim/fcs/mag-switch-left", l_mag);
  setprop ("fdm/jsbsim/fcs/mag-switch-right", r_mag);
  
  #all the below  has to do with friction, dust, ground contact etc so if we're way about the ground we're just going to skip it all.  We check in /position, too bec. sometimes one or the other of  ttem freaks out  
  if (typeof(agl_ft)!="nil" and agl_ft > 100 and typeof(agl_ft_alt)!="nil" and agl_ft_alt > 100 )  {
     #We do one more time through the loop after exceeeding 100 ft AGL just to make sure all smoke is turned off
     if (SCJ_readytoquit) {
        return;
     }
     else SCJ_readytoquit=1;
  } else {
     SCJ_readytoquit=0;
  } 
  
  
  var lat = getprop("/position/latitude-deg");
  var lon = getprop("/position/longitude-deg");
  var info = geodinfo(lat, lon);
  
  
  
  #We are using groundspeed_kt to set the rate per second that dust & wake 
  #particles are displayed.  But sometimes under JSBSim groundspeed_kt goes crazy high.
  #Here we make a limited version of groundspeed that will suit our purposes
  #and always remain within sane bounds
  var groundspeed_kt = getprop("/velocities/groundspeed-kt");
  var groundspeed_kt_trimmed=groundspeed_kt;
  if (groundspeed_kt_trimmed==nil) groundspeed_kt_trimmed=0;
  
  var chocksin=0;
  #implement chocks.
  if (groundspeed_kt_trimmed < 1 and groundspeed_kt_trimmed > -1 and getprop("controls/gear/brake-parking") and agl_ft < 4.6 and agl_ft > 0 ) {
    setprop("velocities/airspeed-kt", 0);
    chocksin=1;
    camelStatusPopupTip ("Chocks are in - Shift-B to remove", 0.2);
    
  } else setprop("controls/gear/brake-parking", 0); # if flying etc turn chocks off 
  
  if (groundspeed_kt_trimmed<0) groundspeed_kt_trimmed=0;
  if (groundspeed_kt_trimmed>75) groundspeed_kt_trimmed=75;
  var wake_dust_rate=groundspeed_kt_trimmed;
  setprop("/environment/terrain-info/wake-dust-rate", wake_dust_rate);
  if ((info != nil) and info[1].solid==0 and groundspeed_kt_trimmed<10)  {
             wake_dust_rate=math.sqrt(math.sqrt(math.sqrt(math.sqrt(groundspeed_kt_trimmed/10))))*20; }
  setprop("/environment/terrain-info/wake-dust-rate", wake_dust_rate); 
             

    

  if ( (info != nil) and (info[1] != nil) ) { #rand()<.1 slows down the rate of bumpiness, which seems to work better than doing it too frequently   
          if (info[1].solid ==nil) info[1].solid = 1;
          setprop("/environment/terrain-info/terrain",info[1].solid);   # 1 if solid land, 0 if water
          #the crash-detect subroutine can only read within the /fdim/jsbsim hierarchy so we must put this there as well
          setprop("/fdm/jsbsim/terrain-info/terrain",info[1].solid);   # 1 if solid land, 0 if water

          # If on water we're going to #1 double the wake rate because water puts up a bunch of spray etc. And #2 bolster the wake rate at slow speeds to make more of a splash as the a/c settles into the water etc.
          

          var wheel_speed0_fps=getprop ("/fdm/jsbsim/gear/unit[0]/wheel-speed-fps");
          var wheel_speed2_fps=getprop ("/fdm/jsbsim/gear/unit[2]/wheel-speed-fps");
          var wheel_speed_fps=wheel_speed0_fps;
          if (wheel_speed2_fps> wheel_speed_fps) wheel_speed_fps=wheel_speed2_fps;
          
          if (info[1].bumpiness ==nil) info[1].bumpiness = 0;
          if (info[1].solid == 0 ) info[1].bumpiness = 1.2; # we're making water automatically quite 'bumpy'
          var bumpinesscoeff=info[1].bumpiness*7;  #15 in 1.8
          var speedbumpinesscoeff=20;          
          
          setprop("/environment/terrain-info/terrain-bumpiness",info[1].bumpiness);

          if (rand()<.2) {   # we do the gear height adjustments only part of the time to reduce the frequency of the bumps and make them more realistic

              # we're experimenting with special paramenters for water to make it more realistic.   
              
              if (info[1].solid == 0 ) { #ie, over water
                # if the a/c is far enough under water that the prop strikes water, then the engine quits
                if (agl_ft < 3.0) setprop ("/controls/engines/engine/magnetos",0);                                                
                
                # on water, we 'raise the gear' so that the a/c will appear
                # to be partially submerged when it lands
                # this sets the gear contact points to be basically the bottom of the fuselage
    
                #L gear & it's protective structure element
                var bump = left_bump_lowpass.filter ((bumpinesscoeff * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[0]/z-position", -20 + bump );
                setprop ("/fdm/jsbsim/contact/unit[21]/z-position", -20 + bump );
                               
                #R gear & it's protective structure element
                var bump = right_bump_lowpass.filter((bumpinesscoeff * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[1]/z-position", -20 + bump );
                setprop ("/fdm/jsbsim/contact/unit[22]/z-position", -20 + bump );
                
                
                #water gear - same bump for both, a bit different than land gear
                var bump = tail_bump_lowpass.filter((bumpinesscoeff * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[2]/z-position",-60 + bump * 3 );
                setprop ("/fdm/jsbsim/gear/unit[3]/z-position",-60 + bump * 3 );
                
                #tail
                setprop ("/fdm/jsbsim/gear/unit[4]/z-position",-12 + (bumpinesscoeff 
    * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                
                #prop bottom, prop top, upper wing l, middle, r
                setprop ("/fdm/jsbsim/contact/unit[9]/z-position",25);
                setprop ("/fdm/jsbsim/contact/unit[10]/z-position",25);
                setprop ("/fdm/jsbsim/contact/unit[13]/z-position",-25); # this is the bottom of the prop; in water it's not really a hard contact point                 
                setprop ("/fdm/jsbsim/contact/unit[12]/z-position",25);
                setprop ("/fdm/jsbsim/contact/unit[14]/z-position",25);
                setprop ("/fdm/jsbsim/contact/unit[15]/z-position",25);
                setprop ("/fdm/jsbsim/contact/unit[16]/z-position",15);
                setprop ("/fdm/jsbsim/contact/unit[17]/z-position",5);
                setprop ("/fdm/jsbsim/contact/unit[18]/z-position",0);
                setprop ("/fdm/jsbsim/contact/unit[19]/z-position",-5);   
                        
                
              } else { # ie, over land
                # on land we set the gear back to normal levels so that 
                # the a/c rolls/drags across land
                # this sets the gear contact points to be the bottom of the
                # tires/rear dragger
    
    
                var lgearpdist=-65;
                var lgeardist=-55;
                var rgearpdist=-65;
                var rgeardist=-55;
                var lgearbroken = getprop("/fdm/jsbsim/systems/crash-detect/left-gear-broken");
                if (lgearbroken) { 
                   var lgearpdist=-25;
                   var lgeardist=-25;
                }
                var rgearbroken = getprop("/fdm/jsbsim/systems/crash-detect/right-gear-broken");
                if (rgearbroken) { 
                   var rgearpdist=-25;
                   var rgeardist=-25;
                }
    
                #L gear & it's protective structure element
                var bump = left_bump_lowpass.filter ((bumpinesscoeff * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[0]/z-position",lgearpdist + bump );
                setprop ("/fdm/jsbsim/contact/unit[21]/z-position",lgeardist + bump );
                #print ("Camel: LBump " ~ bump); 
                
                #R gear & it's protective structure element
                var bump = right_bump_lowpass.filter ((bumpinesscoeff * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[1]/z-position",rgearpdist + bump );
                setprop ("/fdm/jsbsim/contact/unit[22]/z-position",rgeardist + bump );
                #print ("Camel: RBump " ~ bump);
    
                setprop ("/fdm/jsbsim/gear/unit[2]/z-position",-20);  #Experiment: We set the water gear to -55 here, rather than fully retracting to -20, so that on hard bumps on the solid ground it will emit some dust. But this caused problems when the water gear hit land/dirt & caused a lot of friction plus took some of the load (making the crash data look strange), so un-doing it.
                setprop ("/fdm/jsbsim/gear/unit[3]/z-position",-20);
                
                #tail
                var bump = left_bump_lowpass.filter ((bumpinesscoeff 
    * rand()-bumpinesscoeff)*(rand() < wheel_speed_fps/speedbumpinesscoeff));
                setprop ("/fdm/jsbsim/gear/unit[4]/z-position",-18 + bump);               
                #prop bottom, prop top, upper wing l, middle, r
                setprop ("/fdm/jsbsim/contact/unit[9]/z-position",62);
                setprop ("/fdm/jsbsim/contact/unit[10]/z-position",62);
                setprop ("/fdm/jsbsim/contact/unit[13]/z-position",-52); 
                setprop ("/fdm/jsbsim/contact/unit[12]/z-position",59);
                setprop ("/fdm/jsbsim/contact/unit[14]/z-position",56);
                setprop ("/fdm/jsbsim/contact/unit[15]/z-position",56);
                setprop ("/fdm/jsbsim/contact/unit[16]/z-position",56);
                setprop ("/fdm/jsbsim/contact/unit[16]/z-position",48);
                setprop ("/fdm/jsbsim/contact/unit[17]/z-position",38);
                setprop ("/fdm/jsbsim/contact/unit[18]/z-position",32);
                setprop ("/fdm/jsbsim/contact/unit[19]/z-position",28);       
              
              }
          }     
          if (info[1].load_resistance ==nil) info[1].load_resistance = 1e+30;
          if (info[1].solid == 0 ) info[1].load_resistance = 1; # we're experimenting with special paramenters for water to make it more realistic
          setprop("/environment/terrain-info/terrain-load-resistance",info[1].load_resistance);
          
          if (info[1].friction_factor ==nil) info[1].friction_factor = 1.05; 
          if (info[1].solid == 0 ) info[1].friction_factor = .9; # we're experimenting with special paramenters for water to make it more realistic
          setprop("/environment/terrain-info/terrain-friction-factor",info[1].friction_factor);
                    
          
          
          if (info[1].rolling_friction ==nil) info[1].rolling_friction = 0.02;
          
          # we're experimenting with special paramenters for water to make it more realistic.   
          if (info[1].solid == 0 ) {
            var rfriction=.4;
            if (agl_ft < 5.5) rfriction=.4;
            if (agl_ft < 4.5) rfriction=.6;
            if (agl_ft < 3.75) rfriction=.6;
            if (agl_ft < 3.0) rfriction=.6;
            if (agl_ft < 2.5) rfriction=.6;
            if (agl_ft < 2) rfriction=.9;
            info[1].rolling_friction = rfriction;
            
          }

          if (chocksin) setprop("/environment/terrain-info/terrain-rolling-friction",1); # if chocks are in, rolling friction is at max! 
          else setprop("/environment/terrain-info/terrain-rolling-friction",info[1].rolling_friction);
          
          if (info[1].names ==nil) info[1].names="";
          setprop("/environment/terrain-info/names",info[1].names[0]); 
                   
      } else {  #no data received, so these are the defaults
        setprop("/environment/terrain-info/terrain",1);  # 1 if solid land, 0 if water
        #the crash-detect subroutine can only read within the /fdim/jsbsim hierarchy so we must put this there as well
        setprop("/fdm/jsbsim/terrain-info/terrain",1);   # 1 if solid land, 0 if water

        setprop("/environment/terrain-info/terrain-load-resistance",1e+30);
        setprop("/environment/terrain-info/terrain-friction-factor",1.05);
        setprop("/environment/terrain-info/terrain-bumpiness",0);
        setprop("/environment/terrain-info/terrain-rolling-friction",0.02);        
        if (chocksin) setprop("/environment/terrain-info/terrain-rolling-friction",1); # if chocks are in, rolling friction is at max! 
        else setprop("/environment/terrain-info/terrain-rolling-friction",0.02);
      }
      
  #updates friction data for each contact point/gear element based on current location
  friction_loop();
  
  #creates a trimmed version of the current compression-ft amount
  #for each gear setting/element point for use in the wake/dust particle system    
  contact_point_compression_limiter_loop(0,5,wake_dust_rate);
}


########################################################################
#
#FRICTION INIT
#

var friction_init = func {
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
    
    #print ("Camel/JSBSim: Aircraft friction parameters initialized");
  } 
}  

########################################################################
#
#FRICTION LOOP
#
    
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

###################################################################
#COMPRESSION_FT TRIM AND WAKE/DUST FACTOR CALCULATION LOOP 
#this gets the amount of compression for each contact point or gear element
#but (important!) trims it down to between min & max
#this is used in the wake/dust particle system. 
#
#Then it multiplies it by a trimmed version of the current groundspeed (
#calculated above).
#
#That way our wake or dust is proportional to both the speed and the amount of 
#pressure on that contact point. We might be able to add other interesting
#factors later, such as the type of terrain (water, ground, paved, unpaved, etc)
#
#See camel-effect.xml and the files in Models\Effects\wake for more info
#
#camel-effect.xml is loaded in the file sopwithCamel-model-Y.xml (or whichever
#other model file you want to use for the JSBSim Camel - right now it is 
#sopwithCamel-model-Y.xml, which is specified/loaded in 
#sopwithCamel-JSBSim-Bombable-set.xml ). Then the effects are 
#controlled by the code below.
#   
var contact_point_compression_limiter_loop = func ( min=0, max=5, low_limit=.005, zero_round=.00001, multiplier=10) {                                              

     
     for (var n=0;n<getprop("/fdm/jsbsim/gear/num-units"); n+=1) {
        unitName= "unit[" ~ n ~ "]";
        
        #get the value from the Gear OR the contact tree (each element is in one or the other but not both)
        var compression_ft_trimmed=getprop ( "/fdm/jsbsim/gear/" ~unitName~"/compression-ft" );
        if (compression_ft_trimmed==nil or compression_ft_trimmed==0 ) compression_ft_trimmed=getprop ( "/fdm/jsbsim/contact/" ~unitName~"/compression-ft" );
        
        if (compression_ft_trimmed==nil) compression_ft_trimmed=0;
        if (compression_ft_trimmed<min) compression_ft_trimmed=min;
       
         
        if (compression_ft_trimmed>max) compression_ft_trimmed=max;        
        setprop("/environment/terrain-info/gear/"~unitName~"/compression-ft-trimmed", compression_ft_trimmed);
        
        #Units 11, 12 & 13 are the nose & top/bottom of the prop.  If it is 
        #touching the ground & the engine is running we'll kick up a boatload of dust
        var engineRPM = getprop("/engines/engine/rpm");
        var extraMultiplier = 1;
        if (typeof(engineRPM) != "scalar") engineRPM=0;
        if ((num(engineRPM) != nil) and (engineRPM>3 ) and (n==11 or n==12 or n==13)) extraMultiplier =  engineRPM/100;
        #if (engineRPM > 5 and (n==11 or n==12 or n==13)) extraMultiplier = 30 * engineRPM/100;
        
        
        # dust effects look pathetic if the number per second gets too pathetically low
        if (compression_ft_trimmed<zero_round ) compression_ft_trimmed=0;
        
        if (compression_ft_trimmed<low_limit and compression_ft_trimmed>0 ) compression_ft_trimmed=low_limit;
        var wake_dust_factor=compression_ft_trimmed*multiplier*extraMultiplier;
        setprop("/environment/terrain-info/gear/"~unitName~"/wake-dust-factor", wake_dust_factor);     
     }
  
}

#############################################################################
#
#DETECT ANY BROKEN PARTS DUE TO GROUND STRIKE ETC LOOP
#
#This is split off from the above routines because we need to run it at 
#a higher frequency or else we miss out on the fast-moving forces of
#ground collision etc. 120 hz is actually a SLOW rate for simulation of gear & 
#collisions
#

var broken_parts_detector_loop = func (id=0) {
     settimer (func { broken_parts_detector_loop (id) }, 0); 
     
     
     id==broken_parts_detector_loopid or return;                                              
     var propcrash=0; #if the prop hits the ground hard, then we're crashed
     var lgearbroken=0; #if we hit the gear too hard it breaks
     var rgearbroken=0; #if we hit the gear too hard it breaks
     var lcompressionforce=0;
     var rcompressionforce=0;
     
     for (var n=0;n<getprop("/fdm/jsbsim/gear/num-units"); n+=1) {
        
        if (n!=0 and n!=1 and n!=21 and n!=22 and n!=11 and n!=12 and n!=13) continue;   # these are the only parts we are worried about breaking, for now
        unitName= "unit[" ~ n ~ "]";
        #get the value from the Gear OR the contact tree (each element is in one or the other but not both)
        var compression_ft_trimmed=getprop ( "/fdm/jsbsim/gear/" ~unitName~"/compression-ft" );
        if (compression_ft_trimmed==nil or compression_ft_trimmed==0 ) compression_ft_trimmed=getprop ( "/fdm/jsbsim/contact/" ~unitName~"/compression-ft" );
        
        if (compression_ft_trimmed==nil) compression_ft_trimmed=0;
        if (compression_ft_trimmed<0) compression_ft_trimmed=0;
        
        var compression_velocity_fps=getprop ( "/fdm/jsbsim/gear/" ~unitName~"/compression-velocity-fps" );
        if (compression_velocity_fps==nil or compression_velocity_fps==0 ) compression_velocity_fps=getprop ( "/fdm/jsbsim/contact/" ~unitName~"/compression-velocity-fps" );
        
        if (compression_velocity_fps==nil) compression_velocity_fps=0; 
        
        #the old way . . .
        #if ((n==21 and compression_ft_trimmed > 0.5) or (n==0 and compression_ft_trimmed > 1.2)) lgearbroken=1;  #0.2 is very sensitive - for testing
        #if ((n==22 and compression_ft_trimmed > 0.5) or (n==1 and compression_ft_trimmed > 1.2)) rgearbroken=1;
        
        #new improved way of calculating whether the gear is broken.  In
        #many situations the force is taken by both the gear & the protector together
        #TODO: We could also make a special case for when most of the force is horizontal; the gear is likely quite a bit weaker in that direction
        #print ("Camel: parts break running, total lbs " ~ 1000*compression_ft_trimmed ~ " at " ~ n);
        
        ###left gear damaging strike
        if (n==0 or n==21) { #n==0 is left gear, n==21 is left gear protector
           if (n==0) lcompressionforce+= 1000*compression_ft_trimmed;  #1000 is the spring coeff
           if (n==21) lcompressionforce+= 1000*compression_ft_trimmed;
           
           #if (lcompressionforce > 800 ) print ("Camel: L wheel force, " ~lcompressionforce ~ " total lbs, " ~ 1000*compression_ft_trimmed ~ " vel_fps " ~ compression_velocity_fps ~ " at " ~ n);
           if ( 
                lcompressionforce > 1500 
                or (n==0 and compression_ft_trimmed > 1.5)
                or (n==0 and compression_ft_trimmed > 1.0 and (compression_velocity_fps > 20 or compression_velocity_fps < -20) ) # Because we're catching the JSBSim values only once in a while not every one of the 120 hz cycles (bec. JSBSim doesn't 'seem to update them every cycle, or something?  It's confusing.) we're going to make an assumption about what high gear compression PLUS high compressional velocity means.  - vel is actually worse than + vel of the same absolute value, as that means it's just on the rebound from an even higher value, & there is damping & reduce spring force on the return.  
                or (n==0 and compression_ft_trimmed > 1.1 and (compression_velocity_fps > 10 or compression_velocity_fps < -10) )
                or (n==21 and compression_ft_trimmed> 0.5)) #  This could be a front our side force, where the struts have quite a bit lower strength
              {
               lgearbroken=1;   
               print (sprintf("Camel: Broke L wheel, %.0f total lbs, %.0f lbs this gear, %.2f vel_fps at %i", lcompressionforce, 1000*compression_ft_trimmed, compression_velocity_fps,n));
           }   
        }
        
        ###RIGHT gear damaging strike
        if (n==1 or n==22) { #n==0 is left gear, n==21 is left gear protector
           if (n==1) rcompressionforce+= 1000*compression_ft_trimmed;  #1000 is the spring coeff as defined in the jsb.xml file
           if (n==22) rcompressionforce+= 1000*compression_ft_trimmed;
           #if (rcompressionforce > 800 ) print ("Camel: R wheel force, " ~rcompressionforce ~ " total lbs, " ~ 1000*compression_ft_trimmed ~ " vel_fps " ~ compression_velocity_fps ~ " at " ~ n);
           if ( 
                rcompressionforce > 1500 
                or (n==1 and compression_ft_trimmed > 1.5)
                or (n==1 and compression_ft_trimmed > 1.0 and (compression_velocity_fps > 20 or compression_velocity_fps < -20) ) # See note bove
                or (n==1 and compression_ft_trimmed > 1.2 and (compression_velocity_fps > 10 or compression_velocity_fps < -10) )
                or (n==22 and compression_ft_trimmed> 0.5)) # this allows for a great total force OR sufficient bottom or side force to break it 
              {
             rgearbroken=1;     
             print (sprintf("Camel: Broke R wheel, %.0f total lbs, %.0f lbs this gear, %.2f vel_fps at %i",rcompressionforce, 1000*compression_ft_trimmed, compression_velocity_fps,n));   
           }
        }
                 
        #detect prop strike 
        if ((n==11 or n==12 or n==13) and compression_ft_trimmed>0.4) {
           var engineRPM = getprop("/engines/engine/rpm");
           if ((num(engineRPM) != nil) and (engineRPM>3 ) )  propcrash=1;
        }
           
        
     }
     
     if (propcrash==1) {
          #Prop hit the ground hard, so we're crashed now.  TODO: We could differentiate between this & some other types of crashes--make a different 'prop hitting the ground horrible sound', whatever.
         setprop("/fdm/jsbsim/systems/crash-detect/prop-strike",1);
         #print ("JSBSim Camel: Prop hit the ground/crashed.");
     } 

     if (lgearbroken) {
         setprop("/fdm/jsbsim/systems/crash-detect/left-gear-broken",1); 
     }
     if (rgearbroken) {
         setprop("/fdm/jsbsim/systems/crash-detect/right-gear-broken",1); 
     } 
     
         
}

#########################################################################
#
#SETCRASH
#

var setCrash= func {
 var crashed = getprop("/fdm/jsbsim/systems/crash-detect/crashed");
 if (!crashed) return;
 
 #only do this if we've been un-crashed for at least 3 seconds
 var setCrash_thisPause_systime=systime();
 #print ("Crash: Time diff:", setCrash_thisPause_systime, " ", setCrash_lastPause_systime);
 var timeSinceLastCrash = setCrash_thisPause_systime - setCrash_lastPause_systime;
 setCrash_lastPause_systime=setCrash_thisPause_systime;
 if ( timeSinceLastCrash < 3 ) return;
 
 var  crashCause = "Airplane crashed ";
 var impact = getprop("/fdm/jsbsim/systems/crash-detect/impact");
 var impact_water = getprop("/fdm/jsbsim/systems/crash-detect/impact-water");
 var over_g = getprop("/fdm/jsbsim/systems/crash-detect/over-g");
 var prop_strike = getprop("/fdm/jsbsim/systems/crash-detect/prop-strike");
 var current_g = getprop("/fdm/jsbsim/accelerations/Nz"); 
 
 if (impact) crashCause ~=" - Ground impact ";
 if (impact_water) {
     crashCause ~=" - Water impact ";
     #Ok, this doesnt' work rem-ing it out.
     #sink(10, .1, .5);
 }
 if (prop_strike) crashCause ~=" - Propeller Strike  ";   
 if (over_g) crashCause ~= sprintf( " - G force %1.1f G exceeded 15G, aircraft destroyed ", current_g);
 
 #freeze/pause/crash
 #setprop ("/sim/freeze/clock", 1);
 #setprop ("/sim/freeze/master", 1);

 camel.dialog.init(450, 0, crashCause); camel.dialog.create(crashCause);
 #view.stepView(1,1); #kicks them out of the A/C ; we'll put them back in at crashmenu.nas if they go back in the plane
 setprop("/sim/current-view/view-number", 7);

 setprop ("/sim/crashed", 1);
 #setprop ("/velocities/airspeed-kt", 0); #make it stop, rather than bouncing etc.
 #And, just go ahead & make sure . . . 
 #settimer ( func {  setprop ("/velocities/airspeed-kt", 0); }, 0.5);
 #settimer ( func {  setprop ("/velocities/airspeed-kt", 0); }, 1.0);
 #settimer ( func {  setprop ("/velocities/airspeed-kt", 0); }, 1.5);

 #Hmm, apparently we can do this with just the verticle velocity, allowing the a/c to slide along the ground etc., rather than just stopping dead.
 #setprop ("/velocities/speed-down-fps", 0); #make it stop, rather than bouncing etc.  But remming this out so that it happens only after 0.15 sec or so, to allow all 'consequences' to happen, like breaking things
 #And, just go ahead & make sure . . .
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 0.15); 
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 0.5);
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 1.0);
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 1.5);
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 2.5);
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 4.5);
 settimer ( func {  setprop ("/velocities/speed-down-fps", 0); }, 7.5);

}

############################################################################
#
#SINK THE A/C IF IT LANDS ON WATER
#

#sinks the ship, glug . . . glug . . . glug
# OK, it doesn't work bec. JSBSim keeps putting the craft on top of the surface again.
var sink = func (distance_ft, rate_ft_per_cycle, time_sec) {
 setprop ("/position/altitude-ft", getprop ("/position/altitude-ft") - rate_ft_per_cycle);
 distance_ft-=rate_ft_per_cycle;
 if (distance_ft<0) return;
 settimer ( func { sink (distance_ft,rate_ft_per_cycle, time_sec) }, time_sec);

}

############################################################################
#
#START ENGINE LOGIC
#

# JSBSim cranks the engines a lot of times before it finally starts
# This is unrealistic for the Camel.  It either starts instantly or 
# not at all.  The following listener implements that functionality.
camel.throttle_save=0;
var list2 = setlistener ( "/engines/engine/cranking", func {
     # if the engines are cranking and it will start the engines
     # immediately 3 out of 4 times, if at least one magneto is on 
       if (getprop("/engines/engine/cranking")  
           and getprop("/controls/engines/engine/starter") 
           and rand() < .75
           and getprop("/controls/engines/engine/magnetos") > 0 ) {
         settimer ( func { 
               if (getprop("/engines/engine/cranking") and getprop("/controls/engines/engine/starter"))
                 camel.throttle_save = getprop("/controls/engines/engine/throttle"); 
                 setprop("/controls/engines/engine/throttle", 0);
                 setprop("/fdm/jsbsim/propulsion/set-running", -1);
                 settimer ( restore_throttle, 1.5);  
         }, 0.2); # start quite immediately , after just 0.2 seconds, as real engines did 
       } else {
         settimer ( func { setprop("/controls/engines/engine/starter", 0); }, .95);
       }     
     }  
  ,0,0 );


###########################################################################
#
#ENGINE STOPS ON INVERTED FLIGHT LOGIC
#

#When the camel goes upside down, its engine runs out of fuel after a while
#according to Over-Burdening the Camel.png, during a slow roll (23 seconds) 
# the engine stops about the time 90 degrees roll is achieved and starts 
# again about the time level flight is re-attained.h 
camel.prev_pilot_g=0;
camel.fuel_reserve=7;
camel.inverted_out_of_fuel=0;

#number of seconds of fuel before the carbeurator runs out in inverted flight/negative Gs 
camel.fuel_reserve_amount=7;
camel.upper_sputter=.6*camel.fuel_reserve_amount;
camel.upper_sputter_diff=camel.fuel_reserve_amount - camel.upper_sputter; 
camel.lower_sputter=.4*camel.fuel_reserve_amount;

var list3 = setlistener ( "/accelerations/pilot-gdamped", func {
     # if the engines are cranking and it will start the engines
     # immediately once out of 3 times, if at least one magneto is on
       camel.curr_pilot_g=getprop("/accelerations/pilot-gdamped");
       var time_elapsed=getprop("/sim/time/delta-sec");
       if (camel.curr_pilot_g>=.3) {
          camel.fuel_reserve += time_elapsed;
          #print ("Camel: Fuel Reserve - " , camel.fuel_reserve);
          if ( camel.fuel_reserve > camel.fuel_reserve_amount )
              camel.fuel_reserve = camel.fuel_reserve_amount;
       } else if ( camel.curr_pilot_g<=.1 ) {
          camel.fuel_reserve -= time_elapsed;
          #print ("Camel: Fuel Reserve - " , camel.fuel_reserve);
          if ( camel.fuel_reserve < 0 )
              camel.fuel_reserve = 0;
       
       }                 
       var blipped = getprop("sim/model/camel/blip_switch");           
       if (camel.fuel_reserve >= camel.fuel_reserve_amount and 
          camel.inverted_out_of_fuel==1) {  
           
           #turn the engine back on ONLY IF BLIP SWITCH IS NOT DEPRESSED. 
           #if blip switch is depressed, the engines will turn back on when it
           #is released now.           
           if (typeof(blipped)=="nil" or !blipped) camel.magneto.updateMagnetos();
           
           camel.inverted_out_of_fuel=0;
           #print ("Camel: Un-inverted, blipping engine back on");
           #print ( camel.curr_pilot_g);
           #print (camel.prev_pilot_g); 
            
       } else if (camel.fuel_reserve <= 0 and 
          camel.inverted_out_of_fuel==0) {
           #print ("Camel: Inverted, blipping engine off");
           #print (camel.curr_pilot_g);
           #print (camel.prev_pilot_g);
           camel.magneto.magnetos.setValue(0);
           camel.inverted_out_of_fuel=1;
         
       # the next two cases make the engine sputter gradually off 
       # if the carb is just running out of fuel or sputter gradually
       # back on if it is just getting fuel back
       # This uses the magneto class in models/camel-utils.nas to turn
       # the magnetos off or turn them back on (to the state indicated 
       # by the two magneto switches)                              
       } else if (camel.fuel_reserve > camel.upper_sputter and 
          camel.inverted_out_of_fuel==1 and (rand() < time_elapsed*20)) {
           if (rand()> (camel.fuel_reserve - camel.upper_sputter)/camel.upper_sputter_diff) 
               camel.magneto.magnetos.setValue(0);
            else camel.magneto.updateMagnetos();
            #print ("Camel: Sputtering off");
       }  else if (camel.fuel_reserve < camel.lower_sputter and 
          camel.inverted_out_of_fuel==0 and (rand() < time_elapsed*20)) {
           if (rand()< (camel.fuel_reserve/camel.lower_sputter) ) {
               #don't de-sputter if the blip switch is on . . . 
               if (typeof(blipped)=="nil" or !blipped) camel.magneto.updateMagnetos();
           }    
           else camel.magneto.magnetos.setValue(0);
           #print ("Camel: Sputtering on");         
       }     
       
       camel.prev_pilot_g=camel.curr_pilot_g;
           
     }  
  ,0,0 );
  


###########################################################################
#
#VARIOUS INITIALIZERS for routines above 
#
#

friction_init();
# We're disabling JSBSim/FlightGear ground friction stuff because we have our own/better version
# Reason is that the Camel is designed to land in fields etc & did it all the time.  Whereas modern aircraft, not so much.
setprop("/sim/fdm/surface/override-level", 1); 

terrain_servol_loop_start();

var broken_parts_detector_loopid=getprop("/environment/terrain-info/broken_parts_detector_loopid");
if (broken_parts_detector_loopid==nil) broken_parts_detector_loopid=0;
broken_parts_detector_loopid+=1;
setprop("/environment/terrain-info/broken_parts_detector_loopid", broken_parts_detector_loopid);
broken_parts_detector_loop(broken_parts_detector_loopid);  

restore_throttle = func  { 
    setprop("/controls/engines/engine/throttle", camel.throttle_save);
}    

#removelistener(list1);
var setCrash_lastPause_systime=systime();
var list1 = setlistener ( "/fdm/jsbsim/systems/crash-detect/crashed", func { setCrash() },0,0 );


####END INITIALIZERS#########################################################