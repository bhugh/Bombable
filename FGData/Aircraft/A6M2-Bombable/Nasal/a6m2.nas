# A6M2 Zero-Flighter

#
# Zero Flight's Gear class
# This class simulates the Zero's landing gears that
# one gear moves at a time.
#
ZeroGear = {
  new : func {
    var obj = { parents : [ZeroGear],
            gear_direction : 1,
	    gear_changing : 0,
	    delay : 6,
            first_gear : "/gear/gear[0]/position-norm",
	    second_gear : "/gear/gear[1]/position-norm" };
    setlistener("/controls/gear/gear-down", func { obj.transform(); });
    setprop(obj.first_gear, 1);
    setprop(obj.second_gear, 1);
    return obj;
  },

  #
  # transform the gears
  #
  transform : func {
    var last_direction = me.gear_direction;
    me.gear_direction = getprop("/controls/gear/gear-down");
    if (last_direction != me.gear_direction) {
      interpolate(me.first_gear, me.gear_direction, me.delay);
      settimer(func { me.transformSecondGear(); }, me.delay);
      me.gear_changing = 1;
    }
  },

  #
  # Starts changing the position of the second gear
  #
  transformSecondGear : func {
    interpolate(me.second_gear, me.gear_direction, me.delay);
    me.gear_changing = 0;
  }
};

#
# livery initialization
#
aircraft.livery.init("Aircraft/A6M2-Bombable/Models/liveries", "sim/model/A6M2/livery/variant");

var a6m2 = JapaneseWarbird.new();
var observers = [Altimeter.new(), BoostGauge.new(), CylinderTemperature.new(), 
                 ExhaustGasTemperature.new(27.9), AutoMixtureControl.new(800)];
foreach (observer; observers) {
    a6m2.addObserver(observer);
}

var zero_gear = ZeroGear.new();
