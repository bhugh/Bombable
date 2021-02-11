reload_guns  = func {

  groundspeed=getprop("velocities/groundspeed-kt");
  engine_rpm=getprop("engines/engine/rpm");
  
  if (groundspeed < 5 and engine_rpm < 5 ) {
    
    setprop ("/ai/submodels/submodel[0]/count", 250);
    setprop ("/ai/submodels/submodel[3]/count", 250);
    setprop ("/ai/submodels/submodel[1]/count", 64);
    setprop ("/ai/submodels/submodel[4]/count", 64);
    setprop ("/ai/submodels/submodel[2]/count", 250);
    setprop ("/ai/submodels/submodel[5]/count", 250);
    
    gui.popupTip ("Guns reloaded--a belt of 250 rounds in each gun.", 5)
    
  } else {
   
    gui.popupTip ("You must be on the ground and engines dead stopped to re-load guns.",5)
  
  }

}                                 