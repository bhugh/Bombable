###############################################################################
##
## Walk view configuration for Sopwith Camel for FlightGear
##
##  Copyright (C) 2010  Vivian Meazza
##  This file is licensed under the GPL license v2 or later.
##
#
################################################################################

# Constraints

#seems to be running before view is initiated?
settimer (func {

  var groundCrew =
      walkview.CircularXYSurface.new([0, 0, -1.50], 10.0);
  
  # Create the view managers.
  
  var groundcrew_walker = walkview.Walker.new("Ground Crew View", groundCrew);
  

}, 3);