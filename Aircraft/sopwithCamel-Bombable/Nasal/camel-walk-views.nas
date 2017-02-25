###############################################################################
##
## Walk view configuration for Sopwith Camel for FlightGear
##
##  Copyright (C) 2010  Vivian Meazza
##  This file is licensed under the GPL license v2 or later.
##
#
################################################################################
#
# uses Aircraft\Generic\WalkView\ walkview.nas plus Systems/walk-view-keys.xml 
# plus Nasal/camel-walk-views.nas plus setup in -set.xml
#

# Constraints

#seems to be running before view is initiated?
settimer (func {

  var groundCrew =
      walkview.CircularXYSurface.new([0, 0, -1.50], 200.0);
  
  # Create the view managers.
  
  groundcrew_walker = walkview.Walker.new("Inspect Aircraft View", groundCrew);
  

}, 3);