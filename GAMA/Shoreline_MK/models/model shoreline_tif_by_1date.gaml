model tif_shoreline_debug

global {
    grid_file geotif <- grid_file("../includes/Tif_RGBN/2022-07-26-03-23-46_S2_49PBT_MYKHE_RGBN.tif");
    grid_file geotif1 <- grid_file("../includes/Tif_RGBN/2022-07-23-03-06-24_L9_124049_MYKHE_RGBN.tif");  
    file shoreline_file <- file("../includes/L8.shp");
	file shoreline_file1 <- file("../includes/2022_07_23.shp");
    // đặt extent của world theo GeoTIFF
    geometry shape <- envelope(geotif);

    field fff;
    field fff1;

    init {
        fff <- field(geotif);
        fff1 <- field(geotif1);
        create shoreline from: shoreline_file;
        create shoreline1 from: shoreline_file1;
    }
}


species shoreline {
    aspect base {
        draw self.shape color: #yellow border: #yellow width: 8;
    }
}
species shoreline1 {
    aspect base {
        draw self.shape color: #red border: #red width: 8;
    }
}

experiment main type: gui {
    output {
        display firstday_view type: 2d {
            mesh fff1 color: fff1.bands scale: 1 triangulation: true smooth: 4;
            species shoreline1 aspect: base;
           }
          
         display nextday_view type: 2d {
			mesh fff color: fff.bands scale: 1 triangulation: true smooth: 4;
			species shoreline aspect: base;
                
        }
    }
    
}
