/**
* Name: building
* Based on the internal empty template. 
* Author: vuhuo
* Tags: 
*/

model building

/* Insert your model definition here */
global {
	file shape_file_buildings <- file("../includes/DH_buildings.shp");
	file shape_file_bounds <- file("../includes/DongHoi_ward.shp");
	geometry shape <- envelope(shape_file_bounds);
	init {		
	  	create ward from: shape_file_bounds;
        create building from: shape_file_buildings with: [
            level::float(read("level"))
        ] {
        	if (self.shape.area<1000)
        	{
        		//do die;
        	}  	
          if (round(level) = 1) { self.color <- #red; }
            else { self.color <- #gray; }
        }
	}

	species building {
		rgb color;
	    float level;
	
	    aspect base {
	        draw shape color: color;
	    }
	}
	species ward {
	    aspect base {
	        draw shape color: #white border: #red;
	    }
	}
	
}


experiment building_bound type: gui {
    output {
        display city_display type:opengl{
            species ward aspect: base;
            species building aspect: base ;
        }
    }
}