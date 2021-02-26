toggle_revi = func {
  revi = aircraft.door.new ("/controls/armament/revi",2);
  if(getprop("/controls/armament/revi/position-norm") > 0) {
      revi.close();
  } else {

      revi.open();
  }
}

